// Delivers a friend's nudge as a push notification.
//
// Habit reminders are NOT sent from here — those are scheduled on-device by
// ReminderService, which works offline and needs no Firebase. Push exists for
// the one thing a local schedule can't do: deliver something another person
// caused, while the app is closed.
//
// Invoked by the `nudges_notify` trigger (see migration 002) via pg_net, once
// per inserted nudge.
//
// Secrets required:
//   FCM_SERVICE_ACCOUNT — Firebase service-account JSON
//   NUDGE_HOOK_SECRET   — shared secret the trigger sends back to us

import { createClient } from "npm:@supabase/supabase-js@2";
import { loadServiceAccount, mintAccessToken, sendPush } from "../_shared/fcm.ts";

interface Payload {
  nudge_id: string;
}

/** "HH:MM[:SS]" → minutes past midnight, or null if unparseable. */
function toMinutes(value: string | null | undefined): number | null {
  if (!value) return null;
  const [h, m] = value.split(":");
  const hours = Number(h);
  const mins = Number(m);
  if (!Number.isFinite(hours) || !Number.isFinite(mins)) return null;
  return hours * 60 + mins;
}

/**
 * Whether the recipient is inside their do-not-disturb window right now.
 * Handles a window that wraps midnight (22:00 → 07:00). Mirrors
 * ReminderService.inQuietHours in the app.
 */
// deno-lint-ignore no-explicit-any
function isQuietNow(profile: any): boolean {
  const start = toMinutes(profile.quiet_hours_start);
  const end = toMinutes(profile.quiet_hours_end);
  if (start === null || end === null || start === end) return false;

  // The recipient's local wall-clock, via their stored IANA zone.
  const zone = profile.timezone || "UTC";
  let local: string;
  try {
    local = new Date().toLocaleTimeString("en-GB", {
      timeZone: zone,
      hour12: false,
      hour: "2-digit",
      minute: "2-digit",
    });
  } catch {
    return false; // unknown zone: deliver rather than silently swallow
  }
  const now = toMinutes(local);
  if (now === null) return false;

  return start < end ? now >= start && now < end : now >= start || now < end;
}

Deno.serve(async (req) => {
  // The function URL is reachable from the internet, and it reads rows with
  // the service role. Require the shared secret so only our own trigger can
  // make it fire.
  const expected = Deno.env.get("NUDGE_HOOK_SECRET");
  if (!expected || req.headers.get("x-nudge-secret") !== expected) {
    return new Response("unauthorized", { status: 401 });
  }

  let payload: Payload;
  try {
    payload = await req.json();
  } catch {
    return new Response("bad payload", { status: 400 });
  }
  if (!payload.nudge_id) return new Response("missing nudge_id", { status: 400 });

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // Read the nudge by id rather than trusting the trigger's payload, so a
  // forged body can't address a push at an arbitrary user.
  const { data: nudge, error } = await supabase
    .from("nudges")
    .select("to_user_id, habit_id, habits(name), profiles!nudges_from_user_id_fkey(display_name)")
    .eq("id", payload.nudge_id)
    .maybeSingle();
  if (error) return new Response(error.message, { status: 500 });
  if (!nudge) return new Response("no such nudge", { status: 404 });

  const { data: tokens } = await supabase
    .from("notification_tokens")
    .select("fcm_token")
    .eq("user_id", nudge.to_user_id);
  if (!tokens || tokens.length === 0) return new Response("no devices");

  // Respect the account-level switch: a nudge is still a notification.
  const { data: profile } = await supabase
    .from("profiles")
    .select("reminders_enabled, timezone, quiet_hours_start, quiet_hours_end")
    .eq("id", nudge.to_user_id)
    .maybeSingle();
  if (profile && profile.reminders_enabled === false) {
    return new Response("notifications disabled");
  }

  // ...and quiet hours. A friend's poke is still a phone buzzing at 3am, and
  // unlike a habit reminder the recipient never asked for this one at this
  // time. Evaluated in the recipient's own timezone, not the server's.
  if (profile && isQuietNow(profile)) {
    return new Response("within quiet hours");
  }

  // deno-lint-ignore no-explicit-any
  const fromName = (nudge as any).profiles?.display_name ?? "A friend";
  // deno-lint-ignore no-explicit-any
  const habitName = (nudge as any).habits?.name ?? "a habit";

  const sa = loadServiceAccount();
  const accessToken = await mintAccessToken(sa);

  let sent = 0;
  const stale: string[] = [];
  for (const { fcm_token } of tokens) {
    const result = await sendPush({
      sa,
      accessToken,
      token: fcm_token,
      title: `${fromName} nudged you`,
      body: `Time for ${habitName}.`,
      data: { habitId: nudge.habit_id, kind: "nudge" },
    });
    if (result.ok) sent++;
    if (result.stale) stale.push(fcm_token);
  }

  if (stale.length > 0) {
    await supabase.from("notification_tokens").delete().in("fcm_token", stale);
  }

  return new Response(`sent ${sent} of ${tokens.length}`);
});
