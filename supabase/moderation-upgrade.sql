-- TLAL moderation upgrade. Run once in Supabase SQL Editor AFTER supabase/schema.sql.
-- Adds takedowns, bans, an audit trail, and admin-only role management.
begin;

alter table public.runs drop constraint if exists runs_status_check;
alter table public.runs add constraint runs_status_check check (status in ('pending','approved','rejected','removed'));

create table if not exists public.user_bans (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  reason text not null check (char_length(trim(reason)) between 3 and 1000),
  created_by uuid not null references public.profiles(id) on delete restrict,
  expires_at timestamptz,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  ended_at timestamptz,
  ended_by uuid references public.profiles(id) on delete set null
);
create index if not exists user_bans_active_user_idx on public.user_bans(user_id, expires_at) where is_active=true;

create table if not exists public.moderation_audit (
  id bigint generated always as identity primary key,
  actor_id uuid references public.profiles(id) on delete set null,
  action text not null,
  target_user_id uuid references public.profiles(id) on delete set null,
  run_id uuid references public.runs(id) on delete set null,
  reason text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists moderation_audit_created_idx on public.moderation_audit(created_at desc);

alter table public.user_bans enable row level security;
alter table public.moderation_audit enable row level security;
drop policy if exists "Staff can view bans" on public.user_bans;
create policy "Staff can view bans" on public.user_bans for select to authenticated
using (user_id=(select auth.uid()) or exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role in ('moderator','admin')));
drop policy if exists "Staff can issue bans" on public.user_bans;
create policy "Staff can issue bans" on public.user_bans for insert to authenticated
with check (
  created_by=(select auth.uid())
  and user_id<>(select auth.uid())
  and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role in ('moderator','admin'))
);
drop policy if exists "Staff can end bans" on public.user_bans;
create policy "Staff can end bans" on public.user_bans for update to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role in ('moderator','admin')))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role in ('moderator','admin')));
drop policy if exists "Staff can read moderation audit" on public.moderation_audit;
create policy "Staff can read moderation audit" on public.moderation_audit for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role in ('moderator','admin')));
revoke all on public.moderation_audit from anon, authenticated;
grant select on public.moderation_audit to authenticated;
revoke all on public.user_bans from anon, authenticated;
grant select, insert, update on public.user_bans to authenticated;

-- Existing users can submit only if they are not currently banned.
drop policy if exists "Signed-in users can submit their own pending runs" on public.runs;
create policy "Signed-in users can submit their own pending runs" on public.runs for insert to authenticated
with check (
  user_id=(select auth.uid()) and status='pending' and reviewed_by is null and reviewed_at is null
  and not exists (
    select 1 from public.user_bans b
    where b.user_id=(select auth.uid()) and b.is_active=true
      and (b.expires_at is null or b.expires_at > now())
  )
);

-- Database-side audit triggers capture status changes and bans even when actions
-- are performed outside the website. Trigger function is not directly executable.
create or replace function public.tlal_audit_moderation()
returns trigger language plpgsql security definer set search_path=''
as $$
declare
  actor uuid := auth.uid();
  target_user uuid;
  target_run uuid;
  action_name text;
  why text;
  detail jsonb := '{}'::jsonb;
begin
  if tg_table_name='runs' then
    if tg_op='UPDATE' and old.status is distinct from new.status then
      target_user := new.user_id; target_run := new.id;
      action_name := 'run_' || new.status;
      why := new.review_note;
      detail := jsonb_build_object('previous_status',old.status,'new_status',new.status);
    else
      return new;
    end if;
  elsif tg_table_name='user_bans' then
    target_user := new.user_id;
    why := new.reason;
    if tg_op='INSERT' then
      action_name := 'user_banned';
      detail := jsonb_build_object('ban_id',new.id,'expires_at',new.expires_at,'permanent',new.expires_at is null);
    elsif tg_op='UPDATE' and old.is_active is distinct from new.is_active and new.is_active=false then
      action_name := 'user_unbanned';
      detail := jsonb_build_object('ban_id',new.id);
    else
      return new;
    end if;
  elsif tg_table_name='profiles' then
    if tg_op='UPDATE' and old.role is distinct from new.role then
      target_user := new.id; action_name := 'role_changed';
      detail := jsonb_build_object('previous_role',old.role,'new_role',new.role);
    else
      return new;
    end if;
  end if;
  insert into public.moderation_audit(actor_id,action,target_user_id,run_id,reason,details)
  values(actor,target_user, target_run, action_name, why, detail);
  return new;
end;
$$;
revoke all on function public.tlal_audit_moderation() from public, anon, authenticated;

drop trigger if exists tlal_audit_run_status on public.runs;
create trigger tlal_audit_run_status after update of status on public.runs
for each row execute function public.tlal_audit_moderation();
drop trigger if exists tlal_audit_bans on public.user_bans;
create trigger tlal_audit_bans after insert or update of is_active on public.user_bans
for each row execute function public.tlal_audit_moderation();
drop trigger if exists tlal_audit_profile_role on public.profiles;
create trigger tlal_audit_profile_role after update of role on public.profiles
for each row execute function public.tlal_audit_moderation();

-- Safe role-change RPC: no browser-side role column grant is added.
create or replace function public.admin_set_profile_role(target_user_id uuid, new_role text)
returns void language plpgsql security definer set search_path=''
as $$
declare actor_role text;
begin
  select role into actor_role from public.profiles where id=auth.uid();
  if actor_role is distinct from 'admin' then
    raise exception 'Only admins can change staff roles' using errcode='42501';
  end if;
  if new_role not in ('runner','moderator','admin') then
    raise exception 'Invalid role' using errcode='22023';
  end if;
  if target_user_id=auth.uid() and new_role<>'admin' and
     (select count(*) from public.profiles where role='admin') <= 1 then
    raise exception 'Cannot remove the last admin' using errcode='23514';
  end if;
  update public.profiles set role=new_role where id=target_user_id;
  if not found then raise exception 'Profile not found' using errcode='P0002'; end if;
end;
$$;
revoke all on function public.admin_set_profile_role(uuid,text) from public, anon;
grant execute on function public.admin_set_profile_role(uuid,text) to authenticated;

commit;
