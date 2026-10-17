-- ===========================================================================
-- Cadence — migration 004: repeat-until-done reminders, account settings,
-- and a richer profile (bio + achievements).
--
-- Idempotent: safe to run more than once. Paste the whole file into the
-- Supabase SQL editor and run it in one go. Apply after 003.
-- ===========================================================================

-- ── 1. Repeat-until-done, per habit ────────────────────────────────────────
--
-- NOT to be confused with the existing `repeat_reminder`, which means
-- "remind me on days this habit isn't even scheduled". These three are the
-- follow-up nag: after the reminder fires, keep prodding until the habit is
-- ticked off (or the caps below run out).
--
-- Scheduling is on-device (flutter_local_notifications), so these columns are
-- only ever read by the app that owns them — the server never fires anything.
-- They live here so the setting survives a reinstall.

alter table habits add column if not exists repeat_until_done bool not null default false;
alter table habits add column if not exists repeat_interval_minutes int not null default 30;
alter table habits add column if not exists repeat_max_count int not null default 3;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'habits_repeat_interval_sane') then
    alter table habits add constraint habits_repeat_interval_sane
      check (repeat_interval_minutes between 5 and 240);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'habits_repeat_count_sane') then
    alter table habits add constraint habits_repeat_count_sane
      check (repeat_max_count between 1 and 5);
  end if;
end $$;

-- ── 2. Account-level settings ──────────────────────────────────────────────
--
-- Quiet hours suppress FOLLOW-UPS only, never a habit's own reminder time —
-- if you deliberately set a reminder for 23:00, silently never delivering it
-- would read as a bug. The nagging is what stops overnight.
--
-- Null start/end means quiet hours are off. The window may wrap midnight
-- (22:00 → 07:00), which the app handles.

alter table profiles add column if not exists quiet_hours_start time;
alter table profiles add column if not exists quiet_hours_end   time;

-- Pre-fills the reminder time on the Add Habit screen. Null = no pre-fill.
alter table profiles add column if not exists default_reminder_time time;

-- Short free-text line shown on your profile. Visible to accepted friends —
-- see the privacy policy note in docs/legal/privacy.html.
alter table profiles add column if not exists bio text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'profiles_bio_length') then
    alter table profiles add constraint profiles_bio_length
      check (bio is null or char_length(bio) <= 160);
  end if;
end $$;

-- Username is user-editable now (it used to be generated at signup and never
-- changed). It is how friends find you, so keep it to a predictable shape and
-- let the existing unique index reject collisions.
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'profiles_username_shape') then
    alter table profiles add constraint profiles_username_shape
      check (username ~ '^[A-Za-z0-9_.]{3,20}$');
  end if;
exception
  when check_violation then
    -- Existing rows predate the rule (signup generated `email_1234` style
    -- names, which fit, but a stray address-derived name might not). Leave
    -- the constraint off rather than failing the whole migration; new writes
    -- are still validated by set_username() below.
    raise notice 'profiles_username_shape not added — existing usernames do not all match';
end $$;

-- Changing username is a rename, not a new identity: friendships, habits and
-- links all key on profiles.id, so nothing breaks. Done as a function so the
-- unique violation comes back as something the app can show a human.
create or replace function set_username(p_username text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Not signed in.' using errcode = 'check_violation';
  end if;

  if p_username !~ '^[A-Za-z0-9_.]{3,20}$' then
    raise exception 'Usernames are 3–20 characters, letters, numbers, dot or underscore.'
      using errcode = 'check_violation';
  end if;

  -- Case-insensitive collision check: @Harish and @harish are the same handle
  -- to a human looking for a friend, and the unique index alone is not.
  if exists (
    select 1 from profiles
    where lower(username) = lower(p_username) and id <> v_uid
  ) then
    raise exception 'That username is taken.' using errcode = 'unique_violation';
  end if;

  update profiles set username = p_username where id = v_uid;
end;
$$;

revoke all on function set_username(text) from public, anon;
grant execute on function set_username(text) to authenticated;

-- ── 3. Achievements ────────────────────────────────────────────────────────
--
-- Stored rather than recomputed so "earned on 3 March" is a real date, and
-- visible to accepted friends.
--
-- `key` is the milestone id (see lib/services/achievement_service.dart for the
-- catalogue). Deliberately not a foreign key to a catalogue table: the rules
-- live in the app, and a retired badge should keep rendering for whoever
-- already earned it rather than breaking a join.

create table if not exists achievements (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references profiles(id) on delete cascade,
  key         text not null check (char_length(key) between 1 and 40),
  unlocked_on date not null default current_date,
  created_at  timestamptz default now(),
  unique(user_id, key)
);

alter table achievements enable row level security;

-- Own badges, plus those of accepted friends. Same shape as the friendship
-- checks elsewhere; achievements is referenced by no other policy, so this
-- adds no circular evaluation (42P17).
drop policy if exists "achievements_select" on achievements;
create policy "achievements_select" on achievements
  for select to authenticated using (
    auth.uid() = user_id
    or exists (
      select 1 from friendships f
      where f.status = 'accepted'
        and ((f.requester_id = auth.uid() and f.addressee_id = achievements.user_id)
          or (f.addressee_id = auth.uid() and f.requester_id = achievements.user_id))
    )
  );

-- Unlocks are client-detected (the rules need the same habit data the app
-- already has in memory). A user can therefore award themselves a badge —
-- accepted: the only person a forged badge impresses is a friend, and the
-- alternative is duplicating every streak rule in SQL to re-derive it.
-- unlocked_on is pinned server-side so at least the date can't be backdated.
drop policy if exists "achievements_insert" on achievements;
create policy "achievements_insert" on achievements
  for insert to authenticated with check (
    auth.uid() = user_id and unlocked_on = current_date
  );

drop policy if exists "achievements_delete" on achievements;
create policy "achievements_delete" on achievements
  for delete to authenticated using (auth.uid() = user_id);

-- No update policy: a badge is unlocked or it isn't. Re-earning is a no-op
-- against the unique constraint.

create index if not exists achievements_user_idx
  on achievements (user_id, unlocked_on desc);

-- Granted explicitly rather than left to Supabase's default privileges for
-- new public tables. Those defaults are why `anon` quietly held EXECUTE on
-- get_friend_activity; state the intent instead of inheriting it.
revoke all on achievements from public, anon;
grant select, insert, delete on achievements to authenticated;

-- ── 4. Quiet hours apply to nudge push too ─────────────────────────────────
--
-- A friend's nudge is still a notification arriving on your phone at 3am.
-- The send-nudge edge function reads these columns alongside
-- reminders_enabled; it runs with the service role, so RLS doesn't apply and
-- no extra grant is needed.

comment on column profiles.quiet_hours_start is
  'Local wall-clock start of do-not-disturb. Null = off. Suppresses reminder follow-ups and nudge push, never a habit''s own reminder time.';
comment on column profiles.quiet_hours_end is
  'Local wall-clock end of do-not-disturb. Window may wrap midnight.';
