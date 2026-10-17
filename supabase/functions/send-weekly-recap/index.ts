// Sends a weekly habit recap push to every user with a push token.
// Called by the pg_cron job in migration 006 every Sunday at 19:00 UTC.
//
// Secrets required (same as send-nudge):
//   FCM_SERVICE_ACCOUNT — Firebase service-account JSON
//   NUDGE_HOOK_SECRET   — not needed here; this is a cron-only endpoint
//
// To deploy:
//   supabase functions deploy send-weekly-recap

import { createClient } from "npm:@supabase/supabase-js@2";
import { loadServiceAccount, mintAccessToken, sendPush } from "../_shared/fcm.ts";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

/** "HH:MM" → minutes past midnight, null if unparseable. */
function toMinutes(v: string | null | undefined): number | null {
  if (!v) return null;
  const [h, m] = v.split(":");
  const hours = Number(h), mins = Number(m);
  if (!Number.isFinite(hours) || !Number.isFinite(mins)) return null;
  return hours * 60 + mins;
}

// deno-lint-ignore no-explicit-any
function isQuietNow(profile: any): boolean {
  const start = toMinutes(profile.quiet_hours_start);
  const end = toMinutes(profile.quiet_hours_end);
  if (start === null || end === null || start === end) return false;
  const zone = profile.timezone || "UTC";
  let local: string;
  try {
    local = new Date().toLocaleTimeString("en-GB", {
      timeZone: zone, hour12: false, hour: "2-digit", minute: "2-digit",
    });
  } catch { return false; }
  const now = toMinutes(local);
  if (now === null) return false;
  return start < end ? now >= start && now < end : now >= start || now < end;
}

Deno.serve(async (_req) => {
  try {
    const sa = await loadServiceAccount();
    const accessToken = await mintAccessToken(sa);
    const projectId = sa.project_id;

    // All users who have push tokens, with profile data for quiet hours.
    const { data: tokens, error: tokErr } = await supabase
      .from("notification_tokens")
      .select("fcm_token, user_id, profiles(quiet_hours_start, quiet_hours_end, timezone, display_name)");

    if (tokErr) throw tokErr;
    if (!tokens?.length) return new Response("no tokens", { status: 200 });

    // Week boundaries: last 7 days in UTC.
    const now = new Date();
    const weekAgo = new Date(now);
    weekAgo.setUTCDate(weekAgo.getUTCDate() - 7);
    const weekAgoIso = weekAgo.toISOString();

    let sent = 0, skipped = 0;
    const stale: string[] = [];

    for (const row of tokens) {
      // deno-lint-ignore no-explicit-any
      const profile = (row as any).profiles;
      if (!profile) continue;
      if (isQuietNow(profile)) { skipped++; continue; }

      // Count completions in the last 7 days for this user.
      const { count: completions } = await supabase
        .from("habit_completions")
        .select("id", { count: "exact", head: true })
        .eq("user_id", row.user_id)
        .gte("completed_on", weekAgoIso.substring(0, 10));

      const body = completions && completions > 0
        ? `${completions} completion${completions === 1 ? "" : "s"} this week. Keep the momentum going! 🔥`
        : "A new week starts now — every streak begins with one habit. 💪";

      const result = await sendPush({
        accessToken,
        projectId,
        token: row.fcm_token,
        title: "Your weekly recap",
        body,
        data: { type: "weekly_recap" },
      });

      if (result.stale) stale.push(row.fcm_token);
      else sent++;
    }

    // Clean up expired tokens.
    if (stale.length) {
      await supabase.from("notification_tokens").delete().in("fcm_token", stale);
    }

    return new Response(
      JSON.stringify({ sent, skipped, stale: stale.length }),
      { headers: { "Content-Type": "application/json" } },
    );
  } catch (err) {
    console.error("send-weekly-recap error:", err);
    return new Response(String(err), { status: 500 });
  }
});
