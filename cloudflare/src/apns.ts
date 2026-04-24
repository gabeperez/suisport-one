// Apple Push Notification service sender.
//
// Uses token-based auth (.p8 key) over HTTP/2. Workers' fetch() speaks
// HTTP/2 natively to api.push.apple.com / api.sandbox.push.apple.com,
// so there's no third-party APNs library needed — the whole
// integration is ~150 lines of WebCrypto + fetch.
//
// Required env:
//   APNS_KEY_ID    — 10-char key identifier from Apple Developer
//   APNS_TEAM_ID   — 10-char team id
//   APNS_BUNDLE_ID — app bundle id, e.g. "gimme.coffee.iHealth"
//   APNS_KEY       — contents of the AuthKey_<ID>.p8 file. We accept
//                    either the raw PEM (starts with "-----BEGIN")
//                    or the stripped base64 body.
//   APNS_ENV?      — "production" | "sandbox". Defaults to production.
//
// JWT tokens are cached in-memory per-isolate with a 50-minute TTL
// (Apple enforces a 60-min max), so the ES256 signing cost amortises
// across the millions of pushes we send each hour. ha.

import type { Env } from "./env.js";

export interface ApnsEnv {
    APNS_KEY_ID?: string;
    APNS_TEAM_ID?: string;
    APNS_BUNDLE_ID?: string;
    APNS_KEY?: string;
    APNS_ENV?: "production" | "sandbox";
}

export function hasApnsConfig(env: ApnsEnv): boolean {
    return !!(env.APNS_KEY_ID && env.APNS_TEAM_ID && env.APNS_BUNDLE_ID && env.APNS_KEY);
}

export interface ApnsNotification {
    deviceToken: string;                 // hex-encoded
    alert: { title: string; body: string };
    /// suisport://<path> to deep-link into the app on tap.
    category?: string;
    threadId?: string;                   // groups notifications in Notification Center
    payload?: Record<string, unknown>;   // custom claim values (deep-link target, feed id, etc.)
    env?: "production" | "sandbox";
}

export interface ApnsResult {
    ok: boolean;
    status: number;
    apnsId?: string;
    reason?: string;
    /// True when APNs says the token is permanently invalid (410 Gone
    /// or 400 BadDeviceToken). The caller should mark the row
    /// disabled_at so we stop retrying.
    invalidToken?: boolean;
}

/// Cached provider JWT per-isolate. APNs allows reuse for up to 60
/// minutes; refresh at 50 to stay comfortably under.
let cachedJwt: { token: string; exp: number; keyId: string } | null = null;

async function providerJwt(env: ApnsEnv): Promise<string> {
    const now = Math.floor(Date.now() / 1000);
    if (cachedJwt && cachedJwt.exp > now + 60 && cachedJwt.keyId === env.APNS_KEY_ID) {
        return cachedJwt.token;
    }
    const header = { alg: "ES256", kid: env.APNS_KEY_ID! };
    const claims = { iss: env.APNS_TEAM_ID!, iat: now };
    const headerB64 = b64url(new TextEncoder().encode(JSON.stringify(header)));
    const claimsB64 = b64url(new TextEncoder().encode(JSON.stringify(claims)));
    const signingInput = `${headerB64}.${claimsB64}`;

    const pkcs8 = pemToPkcs8(env.APNS_KEY!);
    const key = await crypto.subtle.importKey(
        "pkcs8", pkcs8, { name: "ECDSA", namedCurve: "P-256" },
        false, ["sign"]
    );
    const sig = new Uint8Array(await crypto.subtle.sign(
        { name: "ECDSA", hash: "SHA-256" },
        key,
        new TextEncoder().encode(signingInput)
    ));
    const token = `${signingInput}.${b64url(sig)}`;
    cachedJwt = { token, exp: now + 3000, keyId: env.APNS_KEY_ID! };   // 50 min
    return token;
}

export async function sendPush(env: Env, notif: ApnsNotification): Promise<ApnsResult> {
    if (!hasApnsConfig(env)) {
        return { ok: false, status: 0, reason: "apns_not_configured" };
    }
    const useSandbox = (notif.env ?? env.APNS_ENV) === "sandbox";
    const host = useSandbox ? "api.sandbox.push.apple.com" : "api.push.apple.com";
    const url = `https://${host}/3/device/${notif.deviceToken}`;
    const body = {
        aps: {
            alert: notif.alert,
            sound: "default",
            "thread-id": notif.threadId,
            category: notif.category,
        },
        ...(notif.payload ?? {}),
    };
    const jwt = await providerJwt(env);
    const res = await fetch(url, {
        method: "POST",
        headers: {
            "authorization": `bearer ${jwt}`,
            "apns-topic": env.APNS_BUNDLE_ID!,
            "apns-push-type": "alert",
            "apns-priority": "10",
            "content-type": "application/json",
        },
        body: JSON.stringify(body),
    });
    const apnsId = res.headers.get("apns-id") ?? undefined;
    if (res.status === 200) return { ok: true, status: 200, apnsId };

    const text = await res.text();
    let reason: string | undefined;
    try { reason = (JSON.parse(text) as { reason?: string }).reason; } catch { reason = text; }
    const invalidToken =
        res.status === 410 ||
        reason === "BadDeviceToken" ||
        reason === "Unregistered";
    return { ok: false, status: res.status, apnsId, reason, invalidToken };
}

/// Best-effort fan-out to every active token for an athlete. Tokens
/// that APNs reports as permanently invalid get their `disabled_at`
/// set so subsequent sends skip them. Other failures just log +
/// stash the last error for admin inspection.
export async function sendPushToAthlete(
    env: Env,
    athleteId: string,
    alert: ApnsNotification["alert"],
    opts: { threadId?: string; payload?: Record<string, unknown>; category?: string } = {}
): Promise<{ sent: number; failed: number; invalidated: number }> {
    if (!hasApnsConfig(env)) return { sent: 0, failed: 0, invalidated: 0 };
    const tokens = await env.DB.prepare(
        `SELECT token, env FROM push_tokens
         WHERE athlete_id = ? AND disabled_at IS NULL`
    ).bind(athleteId).all<{ token: string; env: string }>();
    let sent = 0, failed = 0, invalidated = 0;
    for (const row of tokens.results ?? []) {
        const r = await sendPush(env, {
            deviceToken: row.token,
            alert,
            threadId: opts.threadId,
            payload: opts.payload,
            category: opts.category,
            env: row.env as "production" | "sandbox",
        });
        if (r.ok) { sent++; continue; }
        failed++;
        if (r.invalidToken) {
            invalidated++;
            await env.DB.prepare(
                `UPDATE push_tokens
                 SET disabled_at = unixepoch(), last_error = ?, last_error_at = unixepoch()
                 WHERE token = ?`
            ).bind(r.reason ?? String(r.status), row.token).run();
        } else {
            await env.DB.prepare(
                `UPDATE push_tokens
                 SET last_error = ?, last_error_at = unixepoch()
                 WHERE token = ?`
            ).bind(r.reason ?? String(r.status), row.token).run();
        }
    }
    return { sent, failed, invalidated };
}

// =========================================================================
// helpers
// =========================================================================

function pemToPkcs8(p8: string): ArrayBuffer {
    const b64 = p8
        .replace(/-----BEGIN PRIVATE KEY-----/g, "")
        .replace(/-----END PRIVATE KEY-----/g, "")
        .replace(/\s+/g, "");
    const bin = atob(b64);
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out.buffer;
}

function b64url(bytes: Uint8Array): string {
    let s = "";
    for (const b of bytes) s += String.fromCharCode(b);
    return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
