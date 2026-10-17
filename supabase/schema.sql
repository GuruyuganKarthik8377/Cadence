-- =============================================================================
-- CADENCE — complete Supabase backend.
--
-- Idempotent: safe to run repeatedly on the same project, and a single run on
-- a brand-new project produces the full backend (tables, RLS, indexes,
-- functions, triggers, storage, realtime).
--
-- NOT an update path on its own. This file is the *initial* schema; the
-- migrations listed at the bottom redefine some of what's here (policies,
-- get_friend_activity, get_current_streak). Re-running this file rolls those
-- redefinitions back, so always re-apply supabase/migrations/ in filename
-- order afterwards.
--
-- Run in the Supabase SQL editor, or:
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/schema.sql
-- =============================================================================

create extension if not exists pg_trgm;

-- -----------------------------------------------------------------------------
-- 1. Tables (FK-safe order)
-- -----------------------------------------------------------------------------

create table if not exists profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  username     text unique not null,
  display_name text not null,
  avatar_url   text,
  created_at   timestamptz default now(),
  updated_at   timestamptz default now()
);

create table if not exists habits (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null references profiles(id) on delete cascade,
  name                text not null,
  icon_key            text not null default 'sparkles',
  category            text not null,
  habit_type          text not null check (habit_type in ('build', 'break', 'custom')),
  custom_type_label   text,
  frequency_type      text not null check (frequency_type in ('daily', 'specific_days', 'times_per_week')),
  specific_days       int[] default '{}',        -- [0=Mon … 6=Sun]
  times_per_week      int default 1,
  duration_value      int default 0,
  duration_unit       text default 'minutes',
  reminder_enabled    bool default false,
  reminder_time       time,                       -- user's LOCAL wall-clock time
  repeat_reminder     bool default false,
  cover_image_url     text,
  is_archived         bool default false,
  created_at          timestamptz default now(),
  updated_at          timestamptz default now()
);

create table if not exists habit_completions (
  id           uuid primary key default gen_random_uuid(),
  habit_id     uuid not null references habits(id) on delete cascade,
  user_id      uuid not null references profiles(id) on delete cascade,
  completed_on date not null,                    -- 'yyyy-MM-dd', no time component
  created_at   timestamptz default now(),
  unique(habit_id, completed_on)                 -- prevents duplicate toggles
);

create table if not exists friendships (
  id            uuid primary key default gen_random_uuid(),
  requester_id  uuid not null references profiles(id) on delete cascade,
  addressee_id  uuid not null references profiles(id) on delete cascade,
  status        text not null default 'pending'
                  check (status in ('pending', 'accepted', 'declined', 'blocked')),
  created_at    timestamptz default now(),
  updated_at    timestamptz default now(),
  unique(requester_id, addressee_id),
  check (requester_id <> addressee_id)           -- can't friend yourself
);

create table if not exists habit_links (
  id              uuid primary key default gen_random_uuid(),
  user_habit_id   uuid not null references habits(id) on delete cascade,
  friend_habit_id uuid not null references habits(id) on delete cascade,
  friendship_id   uuid not null references friendships(id) on delete cascade,
  is_active       bool default true,
  created_at      timestamptz default now(),
  unique(user_habit_id, friend_habit_id)
);

create table if not exists notification_tokens (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references profiles(id) on delete cascade,
  fcm_token   text not null,
  platform    text not null check (platform in ('android', 'ios')),
  created_at  timestamptz default now(),
  updated_at  timestamptz default now(),
  unique(user_id, platform)
);

-- Columns added after the initial release ------------------------------------
alter table habits   add column if not exists is_favorite bool default false;
alter table habits   add column if not exists location_name     text;
alter table habits   add column if not exists location_lat      double precision;
alter table habits   add column if not exists location_lng      double precision;
alter table habits   add column if not exists location_radius_m int not null default 200;
alter table profiles add column if not exists reminders_enabled bool default true;
-- IANA timezone (e.g. 'Asia/Kolkata'), refreshed by the app on each launch.
-- Reminder times are stored as local wall-clock, so the backend needs this to
-- know when "08:00" actually is for a given user.
alter table profiles add column if not exists timezone text default 'UTC';

-- A pending request A→B plus a second request B→A would create two competing
-- rows. Collapse the pair into one unique constraint regardless of direction.
create unique index if not exists friendships_unique_pair
  on friendships (least(requester_id, addressee_id), greatest(requester_id, addressee_id));

-- -----------------------------------------------------------------------------
-- 2. Indexes — every column the app filters, joins, or sorts on
-- -----------------------------------------------------------------------------

create index if not exists habits_user_active_idx
  on habits (user_id) where is_archived = false;
create index if not exists habits_user_archived_idx
  on habits (user_id) where is_archived = true;
create index if not exists habits_reminders_idx
  on habits (reminder_time) where reminder_enabled = true and is_archived = false;

create index if not exists completions_user_date_idx
  on habit_completions (user_id, completed_on desc);
create index if not exists completions_recent_idx
  on habit_completions (created_at desc);

create index if not exists friendships_requester_idx on friendships (requester_id);
create index if not exists friendships_addressee_idx on friendships (addressee_id);
create index if not exists friendships_status_idx    on friendships (status);

create index if not exists habit_links_friendship_idx on habit_links (friendship_id);
create index if not exists habit_links_user_habit_idx on habit_links (user_habit_id);
create index if not exists habit_links_friend_habit_idx on habit_links (friend_habit_id);

create index if not exists notification_tokens_user_idx on notification_tokens (user_id);

-- Friend search uses ILIKE '%query%', which no btree index can serve.
create index if not exists profiles_username_trgm_idx
  on profiles using gin (username gin_trgm_ops);
create index if not exists profiles_display_name_trgm_idx
  on profiles using gin (display_name gin_trgm_ops);

-- -----------------------------------------------------------------------------
-- 3. Row Level Security — enabled on every table, no exceptions
-- -----------------------------------------------------------------------------

alter table profiles            enable row level security;
alter table habits              enable row level security;
alter table habit_completions   enable row level security;
alter table friendships         enable row level security;
alter table habit_links         enable row level security;
alter table notification_tokens enable row level security;

-- profiles ---------------------------------------------------------------

drop policy if exists "profiles_select" on profiles;
create policy "profiles_select" on profiles
  for select to authenticated using (true);

drop policy if exists "profiles_update" on profiles;
create policy "profiles_update" on profiles
  for update to authenticated using (auth.uid() = id);

-- habits -------------------------------------------------------------------

drop policy if exists "habits_select" on habits;
create policy "habits_select" on habits
  for select to authenticated using (auth.uid() = user_id);

-- Friends can see habits that are already linked (for linked-habit display).
-- SUPERSEDED by migration 003: this returns whole rows, locations included.
-- 003 drops it in favour of the friend_habits view.
drop policy if exists "habits_select_linked" on habits;
create policy "habits_select_linked" on habits
  for select to authenticated using (
    exists (
      select 1 from habit_links hl
      join friendships f on f.id = hl.friendship_id
      where f.status = 'accepted'
        and (f.requester_id = auth.uid() or f.addressee_id = auth.uid())
        and (hl.user_habit_id = habits.id or hl.friend_habit_id = habits.id)
    )
  );

-- CADENCE addition (not in the original doc): accepted friends can browse
-- each other's non-archived habits so the "link a habit" picker has
-- something to select from *before* a habit_links row exists. Without this,
-- habits_select_linked alone makes it impossible to ever create the first
-- link. Completions stay gated separately by completions_select below.
-- SUPERSEDED by migration 003 (see habits_select_linked above).
drop policy if exists "habits_select_friends" on habits;
create policy "habits_select_friends" on habits
  for select to authenticated using (
    is_archived = false
    and exists (
      select 1 from friendships f
      where f.status = 'accepted'
        and ((f.requester_id = auth.uid() and f.addressee_id = habits.user_id)
          or (f.addressee_id = auth.uid() and f.requester_id = habits.user_id))
    )
  );

drop policy if exists "habits_insert" on habits;
create policy "habits_insert" on habits
  for insert to authenticated with check (auth.uid() = user_id);

drop policy if exists "habits_update" on habits;
create policy "habits_update" on habits
  for update to authenticated using (auth.uid() = user_id);

drop policy if exists "habits_delete" on habits;
create policy "habits_delete" on habits
  for delete to authenticated using (auth.uid() = user_id);

-- habit_completions ----------------------------------------------------------

drop policy if exists "completions_select" on habit_completions;
create policy "completions_select" on habit_completions
  for select to authenticated using (
    auth.uid() = user_id
    or exists (
      select 1 from habit_links hl
      join friendships f on f.id = hl.friendship_id
      where f.status = 'accepted'
        and (f.requester_id = auth.uid() or f.addressee_id = auth.uid())
        and (hl.user_habit_id = habit_completions.habit_id
             or hl.friend_habit_id = habit_completions.habit_id)
    )
  );

drop policy if exists "completions_insert" on habit_completions;
-- The habits check is not redundant: habit_completions is
-- unique(habit_id, completed_on) with no user_id, so without it anyone
-- holding your habit id can occupy your day-slot and lock you out of
-- completing your own habit. See migration 003.
create policy "completions_insert" on habit_completions
  for insert to authenticated with check (
    auth.uid() = user_id
    and exists (
      select 1 from habits h
      where h.id = habit_completions.habit_id and h.user_id = auth.uid()
    )
  );

drop policy if exists "completions_delete" on habit_completions;
create policy "completions_delete" on habit_completions
  for delete to authenticated using (auth.uid() = user_id);

-- friendships ----------------------------------------------------------------

drop policy if exists "friendships_select" on friendships;
create policy "friendships_select" on friendships
  for select to authenticated
  using (auth.uid() = requester_id or auth.uid() = addressee_id);

drop policy if exists "friendships_insert" on friendships;
create policy "friendships_insert" on friendships
  for insert to authenticated with check (auth.uid() = requester_id);

drop policy if exists "friendships_update" on friendships;
create policy "friendships_update" on friendships
  for update to authenticated
  using (auth.uid() = requester_id or auth.uid() = addressee_id);

-- Either party can end the friendship.
drop policy if exists "friendships_delete" on friendships;
create policy "friendships_delete" on friendships
  for delete to authenticated
  using (auth.uid() = requester_id or auth.uid() = addressee_id);

-- habit_links ------------------------------------------------------------

-- IMPORTANT: habit_links policies must not query `habits` — habits'
-- habits_select_linked policy queries habit_links, and Postgres rejects the
-- resulting circular RLS evaluation (42P17 infinite recursion). Authorize
-- via the friendship row instead.
drop policy if exists "habit_links_select" on habit_links;
create policy "habit_links_select" on habit_links
  for select to authenticated using (
    exists (
      select 1 from friendships f
      where f.id = habit_links.friendship_id
        and (f.requester_id = auth.uid() or f.addressee_id = auth.uid())
    )
  );

drop policy if exists "habit_links_insert" on habit_links;
create policy "habit_links_insert" on habit_links
  for insert to authenticated with check (
    exists (
      select 1 from friendships f
      where f.id = habit_links.friendship_id
        and f.status = 'accepted'
        and (f.requester_id = auth.uid() or f.addressee_id = auth.uid())
    )
  );

drop policy if exists "habit_links_update" on habit_links;
create policy "habit_links_update" on habit_links
  for update to authenticated using (
    exists (
      select 1 from friendships f
      where f.id = habit_links.friendship_id
        and (f.requester_id = auth.uid() or f.addressee_id = auth.uid())
    )
  );

drop policy if exists "habit_links_delete" on habit_links;
create policy "habit_links_delete" on habit_links
  for delete to authenticated using (
    exists (
      select 1 from friendships f
      where f.id = habit_links.friendship_id
        and (f.requester_id = auth.uid() or f.addressee_id = auth.uid())
    )
  );

-- notification_tokens --------------------------------------------------------

drop policy if exists "tokens_select" on notification_tokens;
create policy "tokens_select" on notification_tokens
  for select to authenticated using (auth.uid() = user_id);

drop policy if exists "tokens_insert" on notification_tokens;
create policy "tokens_insert" on notification_tokens
  for insert to authenticated with check (auth.uid() = user_id);

drop policy if exists "tokens_update" on notification_tokens;
create policy "tokens_update" on notification_tokens
  for update to authenticated using (auth.uid() = user_id);

drop policy if exists "tokens_delete" on notification_tokens;
create policy "tokens_delete" on notification_tokens
  for delete to authenticated using (auth.uid() = user_id);

-- -----------------------------------------------------------------------------
-- 4. Functions
--
-- Every SECURITY DEFINER function pins `search_path` — without it a caller can
-- shadow the schema and run arbitrary code with the definer's privileges.
-- -----------------------------------------------------------------------------

-- SUPERSEDED by migration 003, which makes this schedule-aware (rest days,
-- freezes, times_per_week) so it stops disagreeing with Habit.currentStreak.
create or replace function get_current_streak(p_habit_id uuid)
returns int language plpgsql stable set search_path = public as $$
declare
  v_streak int := 0;
  v_day date := current_date;
begin
  loop
    exit when not exists (
      select 1 from habit_completions
      where habit_id = p_habit_id and completed_on = v_day
    );
    v_streak := v_streak + 1;
    v_day := v_day - 1;
  end loop;
  return v_streak;
end;
$$;

-- Batch version — the friends screen needs a streak per linked habit, and
-- calling get_current_streak() in a loop is an N+1 round trip per friend.
create or replace function get_streaks_for_habits(p_habit_ids uuid[])
returns table (habit_id uuid, streak int)
language sql stable set search_path = public as $$
  select id, get_current_streak(id) from unnest(p_habit_ids) as t(id);
$$;

-- The viewer is auth.uid(), never an argument. An earlier version took the
-- viewer as `p_user_id` and scoped every join on it; because the function is
-- security definer, RLS never applied and that argument was the only thing
-- separating one user's feed from another's — which PostgREST lets any
-- authenticated caller set. Migration 002 removed the parameter; this
-- definition matches it so re-running this file can't bring it back.
create or replace function get_friend_activity()
returns table (
  friend_id         uuid,
  friend_name       text,
  friend_avatar_url text,
  habit_id          uuid,
  habit_name        text,
  habit_icon_key    text,
  completion_id     uuid,
  completed_on      date,
  completed_at      timestamptz
) language sql stable security definer set search_path = public as $$
  select
    p.id,
    p.display_name,
    p.avatar_url,
    h.id,
    h.name,
    h.icon_key,
    hc.id,
    hc.completed_on,
    hc.created_at
  from habit_completions hc
  join habits h on h.id = hc.habit_id
  join profiles p on p.id = hc.user_id
  join friendships f
    on f.status = 'accepted'
    and ((f.requester_id = auth.uid() and f.addressee_id = hc.user_id)
      or (f.addressee_id = auth.uid() and f.requester_id = hc.user_id))
  where hc.completed_on >= current_date - 6
    and hc.user_id <> auth.uid()
  order by hc.created_at desc
  limit 50;
$$;
revoke all on function get_friend_activity() from public, anon;
grant execute on function get_friend_activity() to authenticated;


-- Account deletion (Google Play requires in-app account + data deletion).
-- Deleting the auth.users row cascades through profiles into every app table.
create or replace function public.delete_user()
returns void
language sql
security definer
set search_path = ''
as $$
  delete from auth.users where id = auth.uid();
$$;
revoke all on function public.delete_user() from public;
grant execute on function public.delete_user() to authenticated;

-- -----------------------------------------------------------------------------
-- 5. Triggers
-- -----------------------------------------------------------------------------

-- Note: `set search_path = public` and the schema-qualified table name are
-- required — the auth service fires this trigger with an empty search_path,
-- and without them every signup fails with "Database error saving new user".
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, username, display_name, avatar_url)
  values (
    new.id,
    split_part(new.email, '@', 1) || '_' || floor(random() * 9999)::text,
    coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1)),
    new.raw_user_meta_data->>'avatar_url'
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure handle_new_user();

create or replace function update_updated_at()
returns trigger language plpgsql set search_path = public as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists habits_updated_at on habits;
create trigger habits_updated_at before update on habits
  for each row execute procedure update_updated_at();

drop trigger if exists friendships_updated_at on friendships;
create trigger friendships_updated_at before update on friendships
  for each row execute procedure update_updated_at();

drop trigger if exists profiles_updated_at on profiles;
create trigger profiles_updated_at before update on profiles
  for each row execute procedure update_updated_at();

drop trigger if exists notification_tokens_updated_at on notification_tokens;
create trigger notification_tokens_updated_at before update on notification_tokens
  for each row execute procedure update_updated_at();

-- -----------------------------------------------------------------------------
-- 6. Storage — avatars and habit cover images
-- -----------------------------------------------------------------------------

insert into storage.buckets (id, name, public)
values ('user-content', 'user-content', true)
on conflict (id) do nothing;

-- Writes are scoped to the uploader: the file name must start with their uid
-- (the app writes 'avatars/<uid>.jpg' and 'covers/<uid>-<ts>.jpg'). Without
-- this any signed-in user could overwrite anyone else's avatar.
drop policy if exists "user_content_upload" on storage.objects;
create policy "user_content_upload" on storage.objects
  for insert to authenticated with check (
    bucket_id = 'user-content'
    and (storage.foldername(name))[1] in ('avatars', 'covers')
    and split_part((storage.filename(name)), '.', 1) like auth.uid()::text || '%'
  );

drop policy if exists "user_content_update" on storage.objects;
create policy "user_content_update" on storage.objects
  for update to authenticated using (
    bucket_id = 'user-content'
    and split_part((storage.filename(name)), '.', 1) like auth.uid()::text || '%'
  );

drop policy if exists "user_content_delete" on storage.objects;
create policy "user_content_delete" on storage.objects
  for delete to authenticated using (
    bucket_id = 'user-content'
    and split_part((storage.filename(name)), '.', 1) like auth.uid()::text || '%'
  );

-- Covers/avatars are public assets (the bucket is public).
drop policy if exists "user_content_read" on storage.objects;
create policy "user_content_read" on storage.objects
  for select using (bucket_id = 'user-content');

-- -----------------------------------------------------------------------------
-- 7. Realtime — powers the friends list and activity feed live updates
--
-- The client subscribes with the channel/onPostgresChanges API, which fires
-- only on INSERT/UPDATE/DELETE (never on subscribe), so there is no
-- initial-snapshot invalidation loop.
-- -----------------------------------------------------------------------------

do $$
declare t text;
begin
  foreach t in array array['friendships', 'habit_completions', 'habits'] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

-- -----------------------------------------------------------------------------
-- 8. Run sessions — accelerometer-tracked activity logged against a habit
-- -----------------------------------------------------------------------------

create table if not exists run_sessions (
  id                uuid primary key default gen_random_uuid(),
  habit_id          uuid not null references habits(id) on delete cascade,
  user_id           uuid not null references profiles(id) on delete cascade,
  started_at        timestamptz not null,
  duration_seconds  int not null check (duration_seconds >= 0),
  steps             int not null check (steps >= 0),
  distance_meters   double precision not null check (distance_meters >= 0),
  created_at        timestamptz default now()
);

alter table run_sessions enable row level security;

drop policy if exists "run_sessions_select" on run_sessions;
create policy "run_sessions_select" on run_sessions
  for select to authenticated using (auth.uid() = user_id);

drop policy if exists "run_sessions_insert" on run_sessions;
create policy "run_sessions_insert" on run_sessions
  for insert to authenticated with check (
    auth.uid() = user_id
    and exists (
      select 1 from habits h
      where h.id = run_sessions.habit_id and h.user_id = auth.uid()
    )
  );

drop policy if exists "run_sessions_delete" on run_sessions;
create policy "run_sessions_delete" on run_sessions
  for delete to authenticated using (auth.uid() = user_id);

create index if not exists run_sessions_habit_idx
  on run_sessions (habit_id, started_at desc);

-- -----------------------------------------------------------------------------
-- 9. Accelerometer-verified completion for running/walking habits
--
-- A habit whose name or category names "run"/"walk" (word-boundary match,
-- so "running", "walking", "walker" etc. all count, but "Grocery" or
-- "Sunbathe" don't) can only be marked complete for a day that has a
-- corresponding run_sessions row with steps > 0 — i.e. the phone's own
-- accelerometer reported motion. Enforced in the database rather than the UI,
-- so a client that simply skips the run screen and POSTs a completion is
-- refused.
--
-- What it does NOT do is prove the run happened. The accelerometer readings
-- only exist on the phone, so run_sessions is client-supplied by
-- construction: a user can POST a fabricated session for their own habit and
-- satisfy this trigger. Treat the gate as "you can't tick this box by
-- accident or by ignoring the feature", not as anti-cheat. It is deliberately
-- left there: the only person a fabricated run deceives is its author, and
-- plausibility heuristics (steps-per-second bounds and the like) would start
-- an arms race while rejecting the occasional honest short walk.
-- -----------------------------------------------------------------------------

create or replace function is_run_or_walk_habit(p_name text, p_category text)
returns boolean language sql immutable set search_path = public as $$
  select (p_name ~* '\y(run|walk)') or (p_category ~* '\y(run|walk)');
$$;

create or replace function enforce_activity_verification()
returns trigger language plpgsql set search_path = public as $$
declare
  v_name text;
  v_category text;
  v_tz text;
  v_verified boolean;
begin
  select h.name, h.category, coalesce(p.timezone, 'UTC')
    into v_name, v_category, v_tz
  from habits h
  join profiles p on p.id = h.user_id
  where h.id = new.habit_id;

  if is_run_or_walk_habit(v_name, v_category) then
    select exists (
      select 1 from run_sessions rs
      where rs.habit_id = new.habit_id
        and rs.user_id = new.user_id
        and rs.steps > 0
        and (rs.started_at at time zone v_tz)::date = new.completed_on
    ) into v_verified;

    if not v_verified then
      raise exception
        'This habit can only be completed after an accelerometer-tracked run/walk with recorded steps for %', new.completed_on
        using errcode = 'check_violation';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists habit_completions_verify_activity on habit_completions;
create trigger habit_completions_verify_activity
  before insert on habit_completions
  for each row execute procedure enforce_activity_verification();

-- -----------------------------------------------------------------------------
-- 10. Reminder delivery  (SUPERSEDED — no cron, no edge function)
--
-- Habit reminders are scheduled on-device by ReminderService
-- (lib/services/reminder_service.dart) using flutter_local_notifications.
-- A reminder is a purely local, time-based event, so it needs no Firebase
-- project, no edge function and no pg_cron — and it still fires with the
-- phone offline, which the server path never could.
--
-- The previous `send-reminders` function and its every-minute cron were
-- removed: running both would deliver every reminder twice.
--
-- get_due_reminders() went with it — it had been dead code since the move
-- on-device. Push is now used only for nudges (see send-nudge), which is the
-- one case a local schedule can't cover: something another person caused,
-- arriving while the app is closed.
-- -----------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Later migrations
--
-- This file is the initial schema. Changes since then live in
-- supabase/migrations/ and are applied on top, in filename order:
--
--   002_social_and_tracking.sql — habits.sort_order, habits.rest_days,
--     habit_completions.quantity + note, habit_freezes, habit_reactions,
--     nudges, and the profiles freeze allowance.
--   003_ownership_and_privacy.sql — habit-ownership checks on completion,
--     freeze and run-session inserts; the friend_habits view (so friends
--     stop seeing habit locations); completion_details (so friends stop
--     seeing notes and amounts); and a schedule-aware get_current_streak.
--
-- Kept separate rather than inlined here so the running order stays obvious.
-- ---------------------------------------------------------------------------
