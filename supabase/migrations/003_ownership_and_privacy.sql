-- ===========================================================================
-- Cadence — migration 003: habit ownership on writes, column-level privacy
-- for friends, and a schedule-aware server streak.
--
-- Idempotent: safe to run more than once. Paste the whole file into the
-- Supabase SQL editor and run it in one go. Apply after 002.
-- ===========================================================================

-- ── 1. Writes must target a habit you own ──────────────────────────────────
--
-- Every one of these policies checked only `auth.uid() = user_id` — that the
-- row is labelled with your id — never that the habit it points at is yours.
--
-- habit_completions is `unique(habit_id, completed_on)` with no user_id, so
-- there is exactly one row per habit per day *globally*. A friend can read
-- your habit ids (they need them to link habits), so they could insert
-- (your_habit, today) under their own user_id and permanently occupy the
-- slot: your insert then fails 23505, and completions_delete is owner-scoped
-- so you cannot clear it. The row is invisible to both of you — neither
-- client ever queries the other's completions.
--
-- habit_freezes has the same unique(habit_id, frozen_on) shape. run_sessions
-- has no unique constraint, but an unowned insert still feeds the
-- run/walk verification trigger.
--
-- Subquerying `habits` here is safe: no habits policy references
-- habit_completions, habit_freezes or run_sessions, so this adds no circular
-- policy evaluation (42P17).

drop policy if exists "completions_insert" on habit_completions;
create policy "completions_insert" on habit_completions
  for insert to authenticated with check (
    auth.uid() = user_id
    and exists (
      select 1 from habits h
      where h.id = habit_completions.habit_id and h.user_id = auth.uid()
    )
  );

drop policy if exists "freezes_insert" on habit_freezes;
create policy "freezes_insert" on habit_freezes
  for insert to authenticated with check (
    auth.uid() = user_id
    and exists (
      select 1 from habits h
      where h.id = habit_freezes.habit_id and h.user_id = auth.uid()
    )
  );

drop policy if exists "run_sessions_insert" on run_sessions;
create policy "run_sessions_insert" on run_sessions
  for insert to authenticated with check (
    auth.uid() = user_id
    and exists (
      select 1 from habits h
      where h.id = run_sessions.habit_id and h.user_id = auth.uid()
    )
  );

-- ── 2. Friends see habit names, never habit locations ──────────────────────
--
-- docs/legal/privacy.html states: "Habit notes, amounts, and locations are
-- never shared." RLS authorizes rows, not columns, so `habits_select_friends`
-- and `habits_select_linked` handed accepted friends the *whole* habits row —
-- location_name, location_lat and location_lng included. That is a friend's
-- home or gym coordinates, and friendHabitsProvider was already selecting
-- them with a bare select().
--
-- Fix: drop friend access to the base table and expose the safe columns
-- through a view instead. The view is security definer (security_invoker
-- off), so it reads `habits` past RLS — its own WHERE clause, keyed on
-- auth.uid(), is what authorizes the caller. It mirrors the two dropped
-- policies exactly: non-archived habits of an accepted friend (so the link
-- picker has something to pick), plus either side of an existing link
-- regardless of archived status (so a linked habit keeps rendering after
-- the owner archives it).

drop policy if exists "habits_select_friends" on habits;
drop policy if exists "habits_select_linked" on habits;

drop view if exists friend_habits;
create view friend_habits with (security_invoker = off) as
  select
    h.id, h.user_id, h.name, h.icon_key, h.category,
    h.habit_type, h.custom_type_label,
    h.frequency_type, h.specific_days, h.times_per_week, h.rest_days,
    h.duration_value, h.duration_unit,
    h.is_archived, h.sort_order, h.created_at
  from habits h
  where (
    h.is_archived = false
    and exists (
      select 1 from friendships f
      where f.status = 'accepted'
        and ((f.requester_id = auth.uid() and f.addressee_id = h.user_id)
          or (f.addressee_id = auth.uid() and f.requester_id = h.user_id))
    )
  ) or exists (
    select 1 from habit_links hl
    join friendships f on f.id = hl.friendship_id
    where f.status = 'accepted'
      and (f.requester_id = auth.uid() or f.addressee_id = auth.uid())
      and (hl.user_habit_id = h.id or hl.friend_habit_id = h.id)
  );

revoke all on friend_habits from public, anon;
grant select on friend_habits to authenticated;

-- ── 3. Completion notes and amounts leave habit_completions ────────────────
--
-- Same column-vs-row problem: `completions_select` deliberately shows a
-- friend the completions of a linked habit (the activity feed's realtime
-- subscription and habit_reactions both depend on that visibility), which
-- also handed over the free-text `note` and the `quantity` on those rows.
--
-- These can't be split off with a policy, so they move to an owner-only side
-- table. Friends keep seeing *that* a habit was completed and when — which is
-- what the privacy policy promises — and nothing about what was written down.

create table if not exists completion_details (
  completion_id uuid primary key
                references habit_completions(id) on delete cascade,
  user_id       uuid not null references profiles(id) on delete cascade,
  quantity      int check (quantity is null or quantity >= 0),
  note          text,
  created_at    timestamptz default now()
);

alter table completion_details enable row level security;

drop policy if exists "completion_details_select" on completion_details;
create policy "completion_details_select" on completion_details
  for select to authenticated using (auth.uid() = user_id);

drop policy if exists "completion_details_insert" on completion_details;
create policy "completion_details_insert" on completion_details
  for insert to authenticated with check (
    auth.uid() = user_id
    and exists (
      select 1 from habit_completions c
      where c.id = completion_details.completion_id and c.user_id = auth.uid()
    )
  );

drop policy if exists "completion_details_update" on completion_details;
create policy "completion_details_update" on completion_details
  for update to authenticated using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "completion_details_delete" on completion_details;
create policy "completion_details_delete" on completion_details
  for delete to authenticated using (auth.uid() = user_id);

create index if not exists completion_details_user_idx
  on completion_details (user_id);

-- Carry across anything 002 already wrote, then remove the columns. Guarded
-- on the columns still existing so a second run is a no-op.
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'habit_completions'
      and column_name = 'note'
  ) then
    insert into completion_details (completion_id, user_id, quantity, note)
    select c.id, c.user_id, c.quantity, c.note
    from habit_completions c
    where c.quantity is not null or (c.note is not null and c.note <> '')
    on conflict (completion_id) do nothing;

    alter table habit_completions drop column quantity;
    alter table habit_completions drop column note;
  end if;
end $$;

-- ── 4. The server streak now follows the same rules as the app ─────────────
--
-- get_current_streak() counted consecutive calendar days. Habit.currentStreak
-- in Dart counts consecutive *scheduled* days, skips rest days, and lets a
-- streak freeze carry a run across a miss without extending it. The friends
-- list renders the SQL number (via get_streaks_for_habits) while the owner
-- sees the Dart one, so a friend's Mon/Wed/Fri habit read 1 on your screen
-- and 12 on theirs.
--
-- Now security definer, because it has to be: friend visibility for `habits`
-- moved to the friend_habits view above, and habit_freezes is owner-only, so
-- an invoker-rights function can no longer see what it needs to count a
-- friend's streak. The authorization it loses from RLS is done explicitly
-- below — own habit, or a habit belonging to an accepted friend.

create or replace function get_current_streak(p_habit_id uuid)
returns int
language plpgsql stable security definer set search_path = public as $$
declare
  v_habit    habits%rowtype;
  v_day      date;
  v_week     date;
  v_first    date;
  v_dow      int;
  v_count    int;
  v_streak   int := 0;
  v_guard    int := 0;
begin
  select * into v_habit from habits where id = p_habit_id;
  if not found then return 0; end if;

  -- RLS no longer gates this, so authorize by hand.
  if v_habit.user_id <> auth.uid() and not exists (
    select 1 from friendships f
    where f.status = 'accepted'
      and ((f.requester_id = auth.uid() and f.addressee_id = v_habit.user_id)
        or (f.addressee_id = auth.uid() and f.requester_id = v_habit.user_id))
  ) then
    return 0;
  end if;

  v_habit.specific_days := coalesce(v_habit.specific_days, '{}');
  v_habit.rest_days     := coalesce(v_habit.rest_days, '{}');

  -- times_per_week has no fixed days: streaks are counted in whole weeks that
  -- hit the target. The current week is still in progress, so falling short of
  -- it neither counts nor breaks the run.
  if v_habit.frequency_type = 'times_per_week' then
    select min(completed_on) into v_first
      from habit_completions where habit_id = p_habit_id;
    if v_first is null then return 0; end if;

    v_week := date_trunc('week', current_date)::date;
    while v_week >= date_trunc('week', v_first)::date loop
      select count(*) into v_count from habit_completions
        where habit_id = p_habit_id
          and completed_on >= v_week and completed_on < v_week + 7;
      if v_count >= greatest(coalesce(v_habit.times_per_week, 1), 1) then
        v_streak := v_streak + 1;
      elsif v_week <> date_trunc('week', current_date)::date then
        exit;                       -- a finished week fell short
      end if;
      v_week := v_week - 7;
    end loop;
    return v_streak;
  end if;

  -- Nothing is ever scheduled → no streak, and no point walking 3660 days.
  if v_habit.frequency_type = 'specific_days' then
    if not exists (
      select 1 from unnest(v_habit.specific_days) d
      where not (d = any(v_habit.rest_days))
    ) then
      return 0;
    end if;
  elsif not exists (
    select 1 from generate_series(0, 6) d
    where not (d = any(v_habit.rest_days))
  ) then
    return 0;
  end if;

  -- An incomplete today is "pending", not a miss — start from yesterday.
  v_day := current_date;
  if not exists (
    select 1 from habit_completions
    where habit_id = p_habit_id and completed_on = v_day
  ) then
    v_day := v_day - 1;
  end if;

  while v_guard < 3660 loop
    v_dow := extract(isodow from v_day)::int - 1;      -- 0=Mon … 6=Sun
    if not (v_dow = any(v_habit.rest_days))
       and (v_habit.frequency_type = 'daily'
            or v_dow = any(v_habit.specific_days)) then
      if exists (
        select 1 from habit_completions
        where habit_id = p_habit_id and completed_on = v_day
      ) then
        v_streak := v_streak + 1;
      elsif not exists (
        select 1 from habit_freezes
        where habit_id = p_habit_id and frozen_on = v_day
      ) then
        exit;                       -- unprotected miss ends the run
      end if;                       -- a freeze preserves without extending
    end if;
    v_day := v_day - 1;
    v_guard := v_guard + 1;
  end loop;

  return v_streak;
end;
$$;

revoke all on function get_current_streak(uuid) from public, anon;
grant execute on function get_current_streak(uuid) to authenticated;

-- Batch wrapper is unchanged in shape, but re-declared so it picks up the
-- definer function cleanly and stops being callable by anon.
create or replace function get_streaks_for_habits(p_habit_ids uuid[])
returns table (habit_id uuid, streak int)
language sql stable set search_path = public as $$
  select id, get_current_streak(id) from unnest(p_habit_ids) as t(id);
$$;

revoke all on function get_streaks_for_habits(uuid[]) from public, anon;
grant execute on function get_streaks_for_habits(uuid[]) to authenticated;

-- ── 5. Drop the two dead functions ─────────────────────────────────────────
--
-- get_due_reminders() was superseded when reminders moved on-device; nothing
-- has called it since. get_consistency_rate() was never called from the app
-- at all, and still divides by a flat p_days — the exact bug that was fixed
-- in Dart (Habit.completionRateLast30 divides by *scheduled* days instead,
-- because a flat divisor caps a perfect Mon/Wed/Fri habit at 43%). Leaving a
-- known-wrong function lying around is a trap for whoever calls it next.

drop function if exists get_due_reminders();
drop function if exists get_consistency_rate(uuid, int);

-- ── 6. Streak freezes are spent server-side ────────────────────────────────
--
-- The allowance was enforced entirely in the client: it read
-- freezes_remaining, inserted the freeze, then wrote the balance back. Any
-- authenticated user could PATCH their own profile row and hand themselves
-- unlimited freezes, and the read-then-write left a window where two quick
-- taps both saw the same balance.
--
-- This does the whole thing in one statement-level transaction with the
-- profile row locked, and the two columns are removed from what the client
-- may write (RLS authorizes rows, not columns — same reason 002 had to
-- narrow the UPDATE grant on nudges).
--
-- The monthly top-up moved in here too. It used to be a client-side write on
-- profile read, which is exactly the privilege being revoked.

create or replace function use_freeze(p_habit_id uuid, p_date date)
returns int
language plpgsql security definer set search_path = public as $$
declare
  v_uid       uuid := auth.uid();
  v_remaining int;
  v_refilled  date;
  -- Keep in step with Profile.monthlyFreezes (lib/models/profile.dart).
  v_monthly   constant int := 2;
begin
  if v_uid is null then
    raise exception 'Not signed in.' using errcode = 'check_violation';
  end if;

  if not exists (
    select 1 from habits h where h.id = p_habit_id and h.user_id = v_uid
  ) then
    raise exception 'That habit is not yours.' using errcode = 'check_violation';
  end if;

  -- for update: without the lock two rapid taps read the same balance and
  -- one of the spends is free.
  select freezes_remaining, freezes_refilled_on
    into v_remaining, v_refilled
  from profiles where id = v_uid for update;

  -- First spend of a new calendar month tops the allowance back up.
  if v_refilled is null
     or date_trunc('month', v_refilled) < date_trunc('month', current_date) then
    v_remaining := v_monthly;
    v_refilled  := current_date;
  end if;

  if coalesce(v_remaining, 0) <= 0 then
    raise exception 'No streak freezes left this month.'
      using errcode = 'check_violation';
  end if;

  insert into habit_freezes (habit_id, user_id, frozen_on)
  values (p_habit_id, v_uid, p_date)
  on conflict (habit_id, frozen_on) do nothing;

  -- Already frozen: leave the balance alone rather than charging twice.
  if not found then
    return coalesce(v_remaining, 0);
  end if;

  update profiles
     set freezes_remaining   = v_remaining - 1,
         freezes_refilled_on = v_refilled
   where id = v_uid;

  return v_remaining - 1;
end;
$$;

revoke all on function use_freeze(uuid, date) from public, anon;
grant execute on function use_freeze(uuid, date) to authenticated;

-- The balance is now the server's to move. Everything else on the profile
-- stays user-editable.
revoke update on profiles from authenticated;
grant update (username, display_name, avatar_url, reminders_enabled, timezone)
  on profiles to authenticated;
