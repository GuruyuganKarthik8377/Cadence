// FCM HTTP v1 delivery, shared by the edge functions that push.
//
// The legacy /fcm/send server-key API was shut down by Google in June 2024,
// so this mints an OAuth token from a service account instead.
//
// Required secret:
//   FCM_SERVICE_ACCOUNT — full JSON of a Firebase service-account key

export interface ServiceAccount {
  client_email: string;
  private_key: string;
  project_id: string;
}

export function loadServiceAccount(): ServiceAccount {
  const raw = Deno.env.get("FCM_SERVICE_ACCOUNT");
  if (!raw) throw new Error("FCM_SERVICE_ACCOUNT secret not set");
  const sa = JSON.parse(raw);
  if (!sa.client_email || !sa.project_id || !sa.private_key) {
    throw new Error("FCM_SERVICE_ACCOUNT is malformed");
  }
  return sa;
}

function b64url(data: Uint8Array | string): string {
  const bytes = typeof data === "string"
    ? new TextEncoder().encode(data)
    : data;
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export async function mintAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const unsigned = `${header}.${claims}`;

  const pem = sa.private_key
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = new Uint8Array(
    await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      key,
      new TextEncoder().encode(unsigned),
    ),
  );
  const jwt = `${unsigned}.${b64url(sig)}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!res.ok) throw new Error(`token exchange failed: ${await res.text()}`);
  return (await res.json()).access_token as string;
}

/** Sends one notification. Returns true if FCM accepted it, and reports a
 *  dead token separately so the caller can prune it. */
export async function sendPush(opts: {
  sa: ServiceAccount;
  accessToken: string;
  token: string;
  title: string;
  body: string;
  data?: Record<string, string>;
}): Promise<{ ok: boolean; stale: boolean }> {
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${opts.sa.project_id}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${opts.accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token: opts.token,
          notification: { title: opts.title, body: opts.body },
          data: opts.data ?? {},
          android: { priority: "high" },
        },
      }),
    },
  );
  // 404/410 mean the app was uninstalled or the token rotated.
  return {
    ok: res.ok,
    stale: res.status === 404 || res.status === 410,
  };
}
