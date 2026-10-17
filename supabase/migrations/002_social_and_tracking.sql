-- ===========================================================================
-- Cadence — migration 002: reordering, quantity logging, notes,
-- streak freezes / rest days, reactions and nudges.
--
-- Idempotent: safe to run more than once. Paste the whole file into the
-- Supabase SQL editor and run it in one go.
-- ===========================================================================

-- ── habits: ordering and rest days ─────────────────────────────────────────

-- User-defined order on the habits list. Ties fall back to created_at, so
-- existing habits keep their current order until something is dragged.
alter table habits add column if not exists sort_order int not null default 0;

-- Weekdays (0=Mon … 6=Sun) that never count against a streak. Distinct from
-- specific_days: a rest day is skipped over, not treated as a miss.
alter table habits add column if not exists rest_days int[] not null default '{}';

-- ── habit_completions: quantity and notes ──────────────────────────────────

-- How much was actually done, against the habit's duration_value/duration_unit
-- (e.g. 22 of 30 minutes). NULL means a plain binary "done", which is what
-- every existing row is.
alter table habit_completions add column if not exists quantity int;
alter table habit_completions add column if not exists note text;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'habit_completions_quantity_positive'
  ) then
    alter table habit_completions
      add constraint habit_completions_quantity_positive
      check (quantity is null or quantity >= 0);
  end if;
end $$;

-- ── habit_freezes: one-off streak protection ───────────────────────────────

-- A frozen day is neither a completion nor a miss — the streak walks straight
-- past it. Used for "I was sick" / a limited monthly allowance.
create table if not exists habit_freezes (
  id         uuid primary key default gen_random_uuid(),
  habit_id   uuid not null references habits(id) on delete cascade,
  user_id    uuid not null references profiles(id) on delete cascade,
  frozen_on  date not null,
  created_at timestamptz default now(),
  unique(habit_id, frozen_on)
);

alter table habit_freezes enable row level security;

drop policy if exists "freezes_select" on habit_freezes;
create policy "freezes_select" on habit_freezes
  for select to authenticated using (auth.uid() = user_id);

drop policy if exists "freezes_insert" on habit_freezes;
create policy "freezes_insert" on habit_freezes
  for insert to authenticated with check (auth.uid() = user_id);

drop policy if exists "freezes_delete" on habit_freezes;
create policy "freezes_delete" on habit_freezes
  for delete to authenticated using (auth.uid() = user_id);

create index if not exists habit_freezes_habit_idx
  on habit_freezes (habit_id, frozen_on desc);

-- Monthly freeze allowance. Refilled client-side on the 1st.
alter table profiles add column if not exists freezes_remaining int not null default 2;
alter table profiles add column if not exists freezes_refilled_on date;

-- ── habit_reactions: react to a friend's completion ────────────────────────

create table if not exists habit_reactions (
  id            uuid primary key default gen_random_uuid(),
  completion_id uuid not null references habit_completions(id) on delete cascade,
  actor_id      uuid not null references profiles(id) on delete cascade,
  emoji         text not null check (char_length(emoji) between 1 and 8),
  created_at    timestamptz default now(),
  unique(completion_id, actor_id, emoji)
);

alter table habit_reactions enable row level security;

-- Visibility piggybacks on habit_completions' own policy: the subquery is
-- itself filtered by RLS, so you can only see reactions on completions you
-- were already allowed to see. habit_completions never references
-- habit_reactions, so there's no circular policy evaluation (42P17).
drop policy if exists "reactions_select" on habit_reactions;
create policy "reactions_select" on habit_reactions
  for select to authenticated using (
    exists (
      select 1 from habit_completions c where c.id = habit_reactions.completion_id
    )
  );

drop policy if exists "reactions_insert" on habit_reactions;
create policy "reactions_insert" on habit_reactions
  for insert to authenticated with check (
    auth.uid() = actor_id
    and exists (
      select 1 from habit_completions c where c.id = habit_reactions.completion_id
    )
  );

drop policy if exists "reactions_delete" on habit_reactions;
create policy "reactions_delete" on habit_reactions
  for delete to authenticated using (auth.uid() = actor_id);

create index if not exists habit_reactions_completion_idx
  on habit_reactions (completion_id);

-- ── nudges: poke a friend who hasn't done it today ─────────────────────────

create table if not exists nudges (
  id           uuid primary key default gen_random_uuid(),
  from_user_id uuid not null references profiles(id) on delete cascade,
  to_user_id   uuid not null references profiles(id) on delete cascade,
  habit_id     uuid not null references habits(id) on delete cascade,
  message      text check (message is null or char_length(message) <= 140),
  read_at      timestamptz,
  created_at   timestamptz default now(),
  check (from_user_id <> to_user_id)
);

alter table nudges enable row level security;

drop policy if exists "nudges_select" on nudges;
create policy "nudges_select" on nudges
  for select to authenticated
  using (auth.uid() = to_user_id or auth.uid() = from_user_id);

-- Only an accepted friend may nudge, and only as themselves, and only about a
-- habit the recipient actually owns.
--
-- Without the habit check the sender picks any habit id: the recipient's
-- banner renders the habit name, so an attacker could put arbitrary text in a
-- trusted-looking notification, and varying the id also walks straight past
-- nudges_daily_unique (which is keyed on habit_id) to send unlimited nudges.
--
-- Subquerying `habits` is safe here — habits policies never reference nudges,
-- so this adds no circular policy evaluation (42P17).
drop policy if exists "nudges_insert" on nudges;
create policy "nudges_insert" on nudges
  for insert to authenticated with check (
    auth.uid() = from_user_id
    and exists (
      select 1 from friendships f
      where f.status = 'accepted'
        and ((f.requester_id = auth.uid() and f.addressee_id = nudges.to_user_id)
          or (f.addressee_id = auth.uid() and f.requester_id = nudges.to_user_id))
    )
    and exists (
      select 1 from habits h
      where h.id = nudges.habit_id and h.user_id = nudges.to_user_id
    )
  );

-- Recipient marks it read.
drop policy if exists "nudges_update" on nudges;
create policy "nudges_update" on nudges
  for update to authenticated
  using (auth.uid() = to_user_id)
  with check (auth.uid() = to_user_id);

-- RLS authorizes rows, not columns: the policy above would otherwise let a
-- recipient rewrite message, habit_id or from_user_id and reattribute the
-- nudge. Narrow the privilege itself so read_at is the only writable column.
revoke update on nudges from authenticated;
grant update (read_at) on nudges to authenticated;

drop policy if exists "nudges_delete" on nudges;
create policy "nudges_delete" on nudges
  for delete to authenticated
  using (auth.uid() = to_user_id or auth.uid() = from_user_id);

-- Unread-first lookup for the recipient.
create index if not exists nudges_recipient_idx
  on nudges (to_user_id, created_at desc);

-- One nudge per friend per habit per day — stops poke-spam without needing
-- any rate limiting in the app.
-- Note the double parens around the cast: `(x)::date` needs its own outer
-- parens inside an index expression list, or Postgres reads `(x)` as the
-- whole element and has nowhere to attach the trailing `::date`.
create unique index if not exists nudges_daily_unique
  on nudges (from_user_id, to_user_id, habit_id, ((created_at at time zone 'UTC')::date));

-- ── activity feed: expose completion + habit ids ───────────────────────────
--
-- Reactions attach to a completion, so the feed has to hand back the id it is
-- showing. Adding columns to the return type means dropping and recreating
-- rather than `create or replace`.
--
-- SECURITY: the previous signature took the viewer as a `p_user_id` argument
-- and scoped every join on it. Because the function is `security definer` it
-- runs as the table owner, so RLS never applies and that argument was the only
-- thing separating one user's feed from another's — and PostgREST lets any
-- authenticated caller put any uuid in it. Combined with `profiles_select`
-- being `using (true)`, any user could read any other user's entire friend
-- feed. The parameter is now gone rather than merely validated, so no future
-- caller can reintroduce the same mistake.

drop function if exists get_friend_activity(uuid);
drop function if exists get_friend_activity();

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

-- The old signature is callable by anyone until it's gone; make sure a stale
-- copy can't be reached even if an earlier version of this file was applied.
-- `anon` needs naming explicitly: Supabase's default privileges grant EXECUTE
-- to it directly, and revoking from PUBLIC does not remove a direct grant.
-- The function is harmless to anon (auth.uid() is null, so every join misses
-- and it returns []), but there is no reason for it to be reachable at all.
revoke all on function get_friend_activity() from public, anon;
grant execute on function get_friend_activity() to authenticated;

-- ── nudge push delivery (optional — needs Firebase) ────────────────────────
--
-- Habit reminders are on-device and need none of this. Push covers only the
-- case a local schedule can't: a nudge from another person, arriving while
-- the app is closed.
--
-- Run this block ONLY after:
--   1. enabling the pg_net extension (Dashboard → Database → Extensions)
--   2. supabase functions deploy send-nudge
--   3. supabase secrets set FCM_SERVICE_ACCOUNT="$(cat service-account.json)"
--      supabase secrets set NUDGE_HOOK_SECRET="<a long random string>"
--   4. storing the same two values below
--
-- Everything above this line works without it; nudges simply stay in-app.

-- do $$
-- begin
--   perform set_config('app.settings.nudge_hook_secret', '<same random string>', false);
-- end $$;
--
-- create or replace function notify_nudge()
-- returns trigger language plpgsql security definer set search_path = public as $$
-- begin
--   perform net.http_post(
--     url     := 'https://dsrhmrpqscwkeygmguza.supabase.co/functions/v1/send-nudge',
--     headers := jsonb_build_object(
--                  'Content-Type',   'application/json',
--                  'x-nudge-secret', current_setting('app.settings.nudge_hook_secret', true)
--                ),
--     body    := jsonb_build_object('nudge_id', new.id)
--   );
--   return new;
-- end $$;
--
-- drop trigger if exists nudges_notify on nudges;
-- create trigger nudges_notify
--   after insert on nudges
--   for each row execute procedure notify_nudge();
