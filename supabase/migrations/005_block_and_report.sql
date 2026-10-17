-- ===========================================================================
-- Cadence — migration 005: block-a-user, and a lightweight report path.
--
-- Idempotent: safe to run more than once. Paste into the Supabase SQL editor
-- and run. Apply after 004.
--
-- Play reviewers look for both a way to block and a way to report on any
-- social app that lets strangers contact you by handle. Cadence's schema
-- has always allowed 'blocked' as a friendships.status value; nothing until
-- now actually wrote it.
-- ===========================================================================

-- ── 1. friendships gains a "who blocked whom" column ──────────────────────
--
-- status='blocked' alone can't answer "which party did the blocking?" — and
-- that matters for RLS: only the blocker gets to unblock. Stored on the same
-- row as the friendship rather than a side table because the unique-pair
-- index already forces one row per pair, and split state means two places to
-- keep in step.

alter table friendships add column if not exists blocker_id uuid
  references profiles(id) on delete cascade;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'friendships_block_shape') then
    alter table friendships add constraint friendships_block_shape check (
      (status = 'blocked') = (blocker_id is not null)
      and (blocker_id is null
           or blocker_id = requester_id
           or blocker_id = addressee_id)
    );
  end if;
end $$;

create index if not exists friendships_blocker_idx
  on friendships (blocker_id) where blocker_id is not null;

-- ── 2. Direct writes cannot flip a row to blocked, or touch a blocked row ─
--
-- Blocking has to go through block_user(): the RPC below is security definer,
-- sets blocker_id atomically, and rejects self-blocks.
--
-- The two-way narrowing here is important:
--   using — you cannot MODIFY a row that is already blocked (so the blockee
--           can't clear a block by updating it back to pending)
--   with check — you cannot TRANSITION a row TO blocked directly (so a hostile
--           client can't set status='blocked' with blocker_id=null and slip
--           past the check constraint on a subsequent update)

drop policy if exists "friendships_update" on friendships;
create policy "friendships_update" on friendships
  for update to authenticated
  using (
    (auth.uid() = requester_id or auth.uid() = addressee_id)
    and status <> 'blocked'
  )
  with check (
    (auth.uid() = requester_id or auth.uid() = addressee_id)
    and status in ('pending', 'accepted', 'declined')
  );

-- The blockee cannot delete a block by "unfriending" — only the blocker can.
drop policy if exists "friendships_delete" on friendships;
create policy "friendships_delete" on friendships
  for delete to authenticated
  using (
    (auth.uid() = requester_id or auth.uid() = addressee_id)
    and (status <> 'blocked' or blocker_id = auth.uid())
  );

-- Column-level narrowing: `blocker_id` and `status` are never writable
-- directly (blocking goes through the RPC, and status transitions could be
-- forged otherwise). accept/decline still work because the update policy's
-- `with check` allows status in ('pending','accepted','declined').
--
-- Wait — that check runs, but only if the UPDATE statement actually SETS
-- status. Column-level grants decide *which columns an UPDATE may touch at
-- all*. So we grant update on status (needed for accept/decline) and
-- deliberately NOT on blocker_id.
revoke update on friendships from authenticated;
grant update (status) on friendships to authenticated;

-- ── 3. block_user / unblock_user RPCs ─────────────────────────────────────

create or replace function block_user(p_target_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := auth.uid();
  v_existing uuid;
begin
  if v_me is null then
    raise exception 'Not signed in.' using errcode = 'check_violation';
  end if;
  if v_me = p_target_id then
    raise exception 'You cannot block yourself.' using errcode = 'check_violation';
  end if;
  if not exists (select 1 from profiles where id = p_target_id) then
    raise exception 'That user does not exist.' using errcode = 'check_violation';
  end if;

  -- One row per pair regardless of direction — the unique-pair index in the
  -- initial schema guarantees this. Look up by the ordered pair.
  select id into v_existing from friendships
    where least(requester_id, addressee_id) = least(v_me, p_target_id)
      and greatest(requester_id, addressee_id) = greatest(v_me, p_target_id);

  if v_existing is null then
    insert into friendships (requester_id, addressee_id, status, blocker_id)
      values (v_me, p_target_id, 'blocked', v_me);
  else
    update friendships
       set status = 'blocked',
           blocker_id = v_me,
           updated_at = now()
     where id = v_existing;
  end if;
end;
$$;

revoke all on function block_user(uuid) from public, anon;
grant execute on function block_user(uuid) to authenticated;

create or replace function unblock_user(p_target_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare v_me uuid := auth.uid();
begin
  if v_me is null then
    raise exception 'Not signed in.' using errcode = 'check_violation';
  end if;
  -- Only *your* blocks. If v_me isn't the blocker, delete affects 0 rows
  -- (silently) — which is the correct outcome, not an error.
  delete from friendships
    where least(requester_id, addressee_id) = least(v_me, p_target_id)
      and greatest(requester_id, addressee_id) = greatest(v_me, p_target_id)
      and status = 'blocked'
      and blocker_id = v_me;
end;
$$;

revoke all on function unblock_user(uuid) from public, anon;
grant execute on function unblock_user(uuid) to authenticated;

-- ── 4. Reports ────────────────────────────────────────────────────────────
--
-- The moderation UI would go through the service role; users can only ever
-- write reports about others, never read anyone's. Minimal on purpose: Play
-- reviewers want to see a report path, they don't require a full dashboard.

create table if not exists user_reports (
  id          uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references profiles(id) on delete cascade,
  reported_id uuid not null references profiles(id) on delete cascade,
  reason      text check (reason is null or char_length(reason) <= 500),
  created_at  timestamptz default now(),
  check (reporter_id <> reported_id)
);

alter table user_reports enable row level security;

drop policy if exists "reports_insert" on user_reports;
create policy "reports_insert" on user_reports
  for insert to authenticated with check (auth.uid() = reporter_id);

-- No select/update/delete policies: nobody reads their own reports, and
-- moderation happens via the service role.

create index if not exists user_reports_reported_idx
  on user_reports (reported_id, created_at desc);

revoke all on user_reports from public, anon;
grant insert on user_reports to authenticated;
