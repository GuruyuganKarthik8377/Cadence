-- ===========================================================================
-- Cadence — migration 006: freeze shop + weekly-recap scaffolding.
-- Idempotent. Apply after 005.
-- ===========================================================================

-- ── 1. Habit tracks the highest streak milestone at which a freeze was earned
--
-- Stored per-habit so the milestone resets if you start a new streak from zero.
-- Clients use floor(currentStreak/7) > floor(freeze_awarded_at_streak/7) to
-- decide whether to show the "Claim" button — no extra round-trip needed.

alter table habits
  add column if not exists freeze_awarded_at_streak int not null default 0;

-- ── 2. award_freeze RPC ────────────────────────────────────────────────────
--
-- Awards one bonus freeze for each new 7-day streak milestone on a habit.
-- Returns true when a freeze was granted, false when there is nothing to claim.
-- Caps the running balance at 5 so hoarding never breaks the freeze banner math.

create or replace function award_freeze(p_habit_id uuid)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_me          uuid := auth.uid();
  v_streak      int;
  v_last        int;
begin
  if v_me is null then
    raise exception 'Not signed in.' using errcode = 'check_violation';
  end if;

  -- Ownership check — 0 rows = not found or not yours.
  select coalesce(freeze_awarded_at_streak, 0)
    into v_last
    from habits
   where id = p_habit_id and user_id = v_me;

  if not found then
    raise exception 'Habit not found.' using errcode = 'check_violation';
  end if;

  -- Reuse the same streak logic the app uses.
  select get_current_streak(p_habit_id) into v_streak;

  -- A new milestone is floor(streak/7) > floor(last_awarded/7).
  if v_streak < 7 or (v_streak / 7) <= (v_last / 7) then
    return false;
  end if;

  -- Bump balance (cap 5), then mark the milestone.
  update profiles
     set freezes_remaining = least(freezes_remaining + 1, 5)
   where id = v_me;

  update habits
     set freeze_awarded_at_streak = v_streak
   where id = p_habit_id;

  return true;
end;
$$;

revoke all on function award_freeze(uuid) from public, anon;
grant execute on function award_freeze(uuid) to authenticated;

-- ── 3. Weekly recap: pg_cron job (uncomment after enabling pg_cron extension)
--
-- Dashboard → Database → Extensions → enable pg_cron, then run:
--
-- select cron.schedule(
--   'weekly-recap',
--   '0 19 * * 0',   -- every Sunday 19:00 UTC
--   $$
--     select net.http_post(
--       url     := 'https://dsrhmrpqscwkeygmguza.supabase.co/functions/v1/send-weekly-recap',
--       headers := jsonb_build_object(
--                    'Content-Type',  'application/json',
--                    'Authorization', 'Bearer ' || current_setting('app.service_role_key')
--                  ),
--       body    := '{}'::jsonb
--     );
--   $$
-- );
--
-- Set app.service_role_key in Supabase → Settings → Vault, or pass it via
-- the Supabase CLI: supabase secrets set SERVICE_ROLE_KEY=...
