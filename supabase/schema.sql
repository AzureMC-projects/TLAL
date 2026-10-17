-- Run this SQL in a dedicated TLAL Supabase project.
create extension if not exists pgcrypto;
create table if not exists public.profiles(id uuid primary key references auth.users(id) on delete cascade,runner_name text not null unique check(char_length(runner_name) between 2 and 24),bio text not null default '' check(char_length(bio)<=280),role text not null default 'runner' check(role in ('runner','moderator','admin')),created_at timestamptz not null default now());
create table if not exists public.runs(id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles(id) on delete cascade,chapter text not null check(chapter in ('chapter-1','chapter-2','chapter-3','chapter-4')),category text not null check(category in ('any%','100%')),run_time_ms bigint not null check(run_time_ms>0 and run_time_ms<86400000),version text not null check(char_length(version) between 1 and 40),proof_url text not null check(proof_url ~ '^https?://'),notes text check(notes is null or char_length(notes)<=1000),status text not null default 'pending' check(status in ('pending','approved','rejected')),review_note text check(review_note is null or char_length(review_note)<=1000),reviewed_by uuid references public.profiles(id) on delete set null,reviewed_at timestamptz,created_at timestamptz not null default now());
create index if not exists runs_approved_leaderboard_idx on public.runs(chapter,category,run_time_ms asc) where status='approved';
create index if not exists runs_user_history_idx on public.runs(user_id,created_at desc);
create index if not exists runs_moderation_queue_idx on public.runs(created_at asc) where status='pending';
create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path='' as $$
declare n text;
begin
 n:=coalesce(nullif(trim(new.raw_user_meta_data->>'runner_name'),''),'runner_'||substr(new.id::text,1,8));
 n:=substr(regexp_replace(n,'[^a-zA-Z0-9_ -]','','g'),1,24);
 if char_length(n)<2 then n:='runner_'||substr(new.id::text,1,8); end if;
 insert into public.profiles(id,runner_name,role) values(new.id,n,'runner') on conflict do nothing;
 if not found then
   n:='runner_'||substr(new.id::text,1,8);
   insert into public.profiles(id,runner_name,role) values(new.id,n,'runner') on conflict(id) do nothing;
 end if;
 return new;
end; $$;
drop trigger if exists on_auth_user_created_tlal on auth.users;
create trigger on_auth_user_created_tlal after insert on auth.users for each row execute procedure public.handle_new_user();
alter table public.profiles enable row level security;
alter table public.runs enable row level security;
create policy "Profiles are viewable by everyone" on public.profiles for select to anon,authenticated using(true);
create policy "Users can update their own profile" on public.profiles for update to authenticated using((select auth.uid())=id) with check((select auth.uid())=id);
create policy "Approved runs are public" on public.runs for select to anon,authenticated using(status='approved' or user_id=(select auth.uid()) or exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role in ('moderator','admin')));
create policy "Signed-in users can submit their own pending runs" on public.runs for insert to authenticated with check(user_id=(select auth.uid()) and status='pending' and reviewed_by is null and reviewed_at is null);
create policy "Moderators can review runs" on public.runs for update to authenticated using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role in ('moderator','admin'))) with check(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role in ('moderator','admin')));
revoke update on public.profiles from anon,authenticated;
grant update(runner_name,bio) on public.profiles to authenticated;
grant select on public.profiles to anon,authenticated;
grant select,insert on public.runs to anon,authenticated;
grant update(status,review_note,reviewed_by,reviewed_at) on public.runs to authenticated;