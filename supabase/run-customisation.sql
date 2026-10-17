-- TLAL run customisation. Safe to run once in the connected Supabase project.
alter table public.runs
  add column if not exists title text not null default '',
  add column if not exists description text not null default '',
  add column if not exists platform text,
  add column if not exists tags text[] not null default '{}';
alter table public.runs drop constraint if exists runs_title_length_check;
alter table public.runs add constraint runs_title_length_check check (char_length(title) <= 80);
alter table public.runs drop constraint if exists runs_description_length_check;
alter table public.runs add constraint runs_description_length_check check (char_length(description) <= 500);
alter table public.runs drop constraint if exists runs_platform_check;
alter table public.runs add constraint runs_platform_check check (platform is null or platform in ('PC','PlayStation','Xbox','Other'));
alter table public.runs drop constraint if exists runs_tags_count_check;
alter table public.runs add constraint runs_tags_count_check check (cardinality(tags) <= 5);
drop policy if exists "Runners can customise their own run metadata" on public.runs;
create policy "Runners can customise their own run metadata" on public.runs for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
grant update(title, description, platform, tags) on public.runs to authenticated;
