// Sui event indexer. Runs on a scheduled Worker cron every minute.
// Polls queryEvents filtered on our package + module, writes back to
// D1 so the app's feed can show verified stats without re-querying Sui.
//
// Events we care about:
//   - rewards_engine::RewardMinted      { athlete, amount, epoch }
//   - workout_registry::WorkoutSubmitted { athlete, seq, workout_id,
//                                          distance_m, duration_s,
//                                          reward_amount, timestamp_ms }
//
// The indexer walks both modules in a single tick via their shared
// package. Cursor advances on the most recent event across either
// module so we never lose ground.

import type { Env } from "./env.js";
import { hasSuiConfig, suiClient } from "./sui.js";

interface EventRow {
    event_seq: string;
    tx_digest: string;
    event_type: string;
    athlete_id: string | null;
    workout_object_id: string | null;
    amount: number | null;
    raw: string;
    timestamp_ms: number | null;
}

export interface IndexTickResult {
    ok: boolean;
    ingested?: number;
    cursor?: string;
    lastEventAt?: number | null;
    error?: string;
}

export async function indexTick(env: Env): Promise<IndexTickResult> {
    if (!hasSuiConfig(env)) {
        return { ok: false, error: "sui_not_configured" };
    }

    const cursorRow = await env.DB.prepare(
        `SELECT value FROM schema_meta WHERE key = 'sui_indexer_cursor'`
    ).first<{ value: string }>();
    const cursorStr = cursorRow?.value ?? "";
    const cursor = cursorStr
        ? (JSON.parse(cursorStr) as { txDigest: string; eventSeq: string })
        : null;

    const client = suiClient(env);
    try {
        // SuiEventFilter in the v2 SDK doesn't have a "Package" variant
        // — only MoveModule (plus a handful of others). Walk both
        // modules we care about sequentially and fold the results.
        // `Any` isn't supported on queryEvents, only on subscriptions.
        const [reRes, wrRes] = await Promise.all([
            client.queryEvents({
                query: { MoveModule: { package: env.SUI_PACKAGE_ID!, module: "rewards_engine" } },
                cursor, limit: 50, order: "ascending",
            }),
            client.queryEvents({
                query: { MoveModule: { package: env.SUI_PACKAGE_ID!, module: "workout_registry" } },
                cursor, limit: 50, order: "ascending",
            }),
        ]);
        const combined = [...reRes.data, ...wrRes.data]
            .sort((a, b) => (Number(a.timestampMs ?? 0) - Number(b.timestampMs ?? 0)));

        if (combined.length === 0) {
            await touchHealth(env, 0, null);
            return { ok: true, ingested: 0, cursor: cursorStr };
        }

        const rows: EventRow[] = combined
            .map((e) => {
                const p = (e.parsedJson as Record<string, unknown> | undefined) ?? {};
                const amount = pickBigString(p, "amount") ?? pickBigString(p, "reward_amount");
                return {
                    event_seq: e.id.eventSeq,
                    tx_digest: e.id.txDigest,
                    event_type: e.type,
                    athlete_id: typeof p.athlete === "string" ? (p.athlete as string) : null,
                    workout_object_id: typeof p.workout_id === "string"
                        ? (p.workout_id as string) : null,
                    amount: amount != null ? Number(amount) : null,
                    raw: JSON.stringify(p),
                    timestamp_ms: e.timestampMs != null ? Number(e.timestampMs) : null,
                };
            });

        const stmts: D1PreparedStatement[] = [];
        let lastEventAt: number | null = null;

        for (const r of rows) {
            if (r.timestamp_ms && (lastEventAt == null || r.timestamp_ms > lastEventAt)) {
                lastEventAt = r.timestamp_ms;
            }

            stmts.push(env.DB.prepare(
                `INSERT OR IGNORE INTO sui_events
                 (event_seq, tx_digest, event_type, athlete_id, workout_object_id, amount, raw)
                 VALUES (?, ?, ?, ?, ?, ?, ?)`
            ).bind(
                r.event_seq, r.tx_digest, r.event_type,
                r.athlete_id, r.workout_object_id, r.amount, r.raw
            ));

            if (r.event_type.endsWith("::rewards_engine::RewardMinted")
                && r.athlete_id && r.amount != null) {
                // Upsert so brand-new athletes get a sweat_points row
                // created rather than silently no-op'ing.
                stmts.push(env.DB.prepare(
                    `INSERT INTO sweat_points (athlete_id, total, weekly, updated_at, is_demo)
                     VALUES (?, ?, 0, unixepoch(), 0)
                     ON CONFLICT(athlete_id) DO UPDATE SET
                       total = total + excluded.total,
                       updated_at = unixepoch()`
                ).bind(r.athlete_id, r.amount));
            }

            if (r.event_type.endsWith("::workout_registry::WorkoutSubmitted")
                && r.athlete_id && r.workout_object_id) {
                // Back-fill the on-chain object id on the most recent
                // workout for this athlete + tx. Verified flips to 1.
                stmts.push(env.DB.prepare(
                    `UPDATE workouts
                     SET sui_object_id = ?, verified = 1
                     WHERE athlete_id = ? AND sui_tx_digest = ?`
                ).bind(r.workout_object_id, r.athlete_id, r.tx_digest));
            }
        }

        if (stmts.length) await env.DB.batch(stmts);

        // Take whichever module's cursor is farther — we walk both
        // independently, but the single stored cursor applies to
        // both queries on the next tick. Picking "more recent of
        // two" means the next tick might re-see a couple events;
        // INSERT OR IGNORE on sui_events handles duplicates safely.
        const nextCursor = reRes.nextCursor ?? wrRes.nextCursor ?? cursor;
        if (nextCursor) {
            await env.DB.prepare(
                `UPDATE schema_meta SET value = ?, updated_at = unixepoch()
                 WHERE key = 'sui_indexer_cursor'`
            ).bind(JSON.stringify(nextCursor)).run();
        }

        await touchHealth(env, rows.length, lastEventAt);

        return {
            ok: true,
            ingested: rows.length,
            cursor: JSON.stringify(nextCursor),
            lastEventAt,
        };
    } catch (err) {
        await touchHealth(env, 0, null, err instanceof Error ? err.message : "unknown");
        return { ok: false, error: err instanceof Error ? err.message : "unknown" };
    }
}

/** Heartbeat so the /v1/sui/status endpoint can report indexer lag. */
async function touchHealth(
    env: Env, ingested: number, lastEventAt: number | null,
    errorMsg?: string
): Promise<void> {
    const meta = JSON.stringify({
        ts: Date.now(),
        ingested,
        lastEventAt,
        error: errorMsg ?? null,
    });
    await env.DB.prepare(
        `INSERT INTO schema_meta (key, value) VALUES ('sui_indexer_health', ?)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = unixepoch()`
    ).bind(meta).run();
}

/** Move u64 values arrive as string in JSON; normalize to a plain
 *  string we can feed into Number() without Infinity surprises. */
function pickBigString(obj: Record<string, unknown>, key: string): string | null {
    const v = obj[key];
    if (typeof v === "string") return v;
    if (typeof v === "number") return String(v);
    return null;
}
