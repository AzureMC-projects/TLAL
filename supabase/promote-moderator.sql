-- Run this once in Supabase SQL Editor after ItzMunizz has created an account.
-- Promotes only the profile whose runner_name exactly matches ItzMunizz.
update public.profiles
set role = 'moderator'
where lower(trim(runner_name)) = lower('ItzMunizz')
returning id, runner_name, role;
