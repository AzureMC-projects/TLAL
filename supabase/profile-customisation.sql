-- Run once in Supabase SQL Editor to enable the additional standalone profile customisation options.
begin;
alter table public.profiles add column if not exists pronouns text not null default '';
alter table public.profiles add column if not exists banner_url text not null default '';
alter table public.profiles add column if not exists discord_url text not null default '';
alter table public.profiles add column if not exists theme_color text not null default 'red';
alter table public.profiles drop constraint if exists profiles_pronouns_length;
alter table public.profiles add constraint profiles_pronouns_length check (char_length(pronouns)<=32);
alter table public.profiles drop constraint if exists profiles_banner_url_scheme;
alter table public.profiles add constraint profiles_banner_url_scheme check (banner_url='' or banner_url ~ '^https?://');
alter table public.profiles drop constraint if exists profiles_discord_url_scheme;
alter table public.profiles add constraint profiles_discord_url_scheme check (discord_url='' or discord_url ~ '^https?://');
alter table public.profiles drop constraint if exists profiles_theme_color_check;
alter table public.profiles add constraint profiles_theme_color_check check (theme_color in ('red','blue','purple','green','gold'));
grant update(pronouns,banner_url,discord_url,theme_color) on public.profiles to authenticated;
commit;
