# TLAL — The Last Assembly List

Dark horror-inspired speedrun leaderboards for the Poppy Playtime fan game The Last Assembly. This is a fan-made community project, not affiliated with Mob Entertainment.

## Features

- Responsive dark design, chapter filters, Any% and 100% categories.
- Public leaderboard displays approved runs only.
- Supabase account sign-up/sign-in and runner profiles.
- Run submissions with chapter, category, time, version, video proof and notes.
- Submission history and pending/approved/rejected statuses.
- Moderator queue with approve/reject actions.
- Database schema and Row Level Security policies.
- Clearly labelled sample preview until Supabase is configured.

## Standalone profiles and moderation

- Public runner pages use `profile.html?runner=<runner_handle>` and show approved runs, bio, social links, profile banner, avatar, pronouns, country and accent theme.
- Run `supabase/profile-customisation.sql` in the Supabase SQL Editor to add banner, pronouns, Discord and accent-theme columns. Existing profile fields are already in `supabase/schema.sql`.
- The homepage links to individual profiles; the editor is on the runner's own profile page.
- Staff moderation lives at `moderation.html`. Run `supabase/moderation-upgrade.sql` for takedowns, bans, audit history and admin role controls before using those features.

## 1. GitHub Pages

Open https://github.com/AzureMC-projects/TLAL/settings/pages. Choose **Deploy from a branch**, branch **main**, folder **/(root)**, then save. Expected URL: https://azuremc-projects.github.io/TLAL/

## 2. Supabase backend

Use a dedicated Supabase project for TLAL. Do not connect an unrelated production project.

1. Create a project at https://supabase.com/dashboard.
2. Open its SQL Editor and run all of supabase/schema.sql.
3. In Project Settings → API Keys, copy the Project URL and publishable key (sb_publishable_...). A legacy anon key also works.
4. Edit config.js and fill the two empty strings with your project URL and publishable key.
5. Commit config.js. These values are public browser settings. NEVER put a service_role key or secret key in frontend files.
6. In Supabase Authentication → URL Configuration, add https://azuremc-projects.github.io/TLAL/ to Site URL and Redirect URLs. Add http://localhost:8000/ for local testing.
7. Decide whether to require email confirmation and configure email delivery if enabled.

## 3. Promote a trusted moderator

New users always get the runner role. After you sign up and confirm your own account, run this in the Supabase SQL Editor, replacing the email:

    update public.profiles
    set role = 'admin'
    where id = (select id from auth.users where email = 'YOUR-ACCOUNT-EMAIL');

Keep admin access restricted to trusted staff. Never expose a service-role key.

## 4. Local test

From the repository directory, run python -m http.server 8000, then open http://localhost:8000/. Preview mode does not save submissions.

## Launch checklist

- [ ] Enable GitHub Pages on main / root.
- [ ] Create a dedicated Supabase project and run supabase/schema.sql.
- [ ] Add the project URL and publishable key to config.js.
- [ ] Configure Auth redirect URLs and email confirmation.
- [ ] Test account creation, submission, moderation, history and ranking.
- [ ] Replace draft rules with community-agreed speedrun rules.

## Files

- index.html — page structure
- styles.css — responsive dark-horror design
- app.js — auth, submissions, leaderboard and moderation UI
- config.js — public Supabase connection settings
- supabase/schema.sql — tables, trigger, indexes and RLS

## Disclaimer

TLAL is an independent fan-made community leaderboard. Poppy Playtime and related intellectual property belong to their respective rights holders. No official affiliation is claimed.

### Run customisation

Apply `supabase/run-customisation.sql` if you are setting up the run customisation feature manually. Runners can edit title, description, platform, and tags from their own profile. Core run facts and moderation status remain restricted to staff workflows.
