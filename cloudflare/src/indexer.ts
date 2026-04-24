// Sui event indexer. Runs on a scheduled Worker cron every minute.
// Polls queryEvents filtered on our package + module, writes back to
// D1 so the app's feed can show verified stats without re-querying Sui.
//
// Events we care about:
//   - rewards_engine::RewardMinted { athlete, amount, epoch }
//   - workout_registry::WorkoutSubmitted { athlete, seq, workout_id, ... }

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
}

export async function indexTick(env: Env): Promise<{
    ok: boolean;
    ingested?: number;
    cursor?: string;
    error?: string;
}> {
    if (!hasSuiConfig(env)) {
        return { ok: false, error: "sui_not_configured" };
    }

    const cursorRow = await env.DB.prepare(
        `SELECT value FROM schema_meta WHERE key = 'sui_indexer_cursor'`
    ).first<{ value: string }>();
    const cursorStr = cursorRow?.value ?? "";
    const cursor = cursorStr ? (JSON.parse(cursorStr) as { txDigest: string; eventSeq: string }) : null;

    const client = suiClient(env);
    let ingested = 0;
    try {
        const res = await client.queryEvents({
            query: { MoveModule: { package: env.SUI_PACKAGE_ID!, module: "rewards_engine" } },
            cursor,
            limit: 50,
            order: "ascending",
        });

        if (res.data.length === 0) {
            return { ok: true, ingested: 0, cursor: cursorStr };
        }

        const rows: EventRow[] = res.data.map((e) => {
            const parsed = (e.parsedJson as Record<string, unknown> | undefined) ?? {};
            return {
                event_seq: e.id.eventSeq,
                tx_digest: e.id.txDigest,
                event_type: e.type,
                athlete_id: typeof parsed.athlete === "string" ? parsed.athlete as string : null,
                workout_object_id: typeof parsed.workout_id === "string" ? parsed.workout_id as string : null,
                amount: typeof parsed.amount === "string"
                    ? Number(parsed.amount)
                    : (typeof parsed.reward_amount === "string" ? Number(parsed.reward_amount) : null),
                raw: JSON.stringify(parsed),
            };
        });

        const stmts = [];
        for (const r of rows) {
            stmts.push(env.DB.prepare(
                `INSERT OR IGNORE INTO sui_events
                 (event_seq, tx_digest, event_type, athlete_id, workout_object_id, amount, raw)
                 VALUES (?, ?, ?, ?, ?, ?, ?)`
            ).bind(
                r.event_seq, r.tx_digest, r.event_type,
                r.athlete_id, r.workout_object_id, r.amount, r.raw
            ));
            // Back-fill workouts + sweat_points when we see a matching event.
            if (r.event_type.endsWith("::rewards_engine::RewardMinted") && r.athlete_id && r.amount) {
                stmts.push(env.DB.prepare(
                    `UPDATE sweat_points
                     SET total = total + ?, updated_at = unixepoch()
                     WHERE athlete_id = ?`
                ).bind(r.amount, r.athlete_id));
            }
            if (r.event_type.endsWith("::workout_registry::WorkoutSubmitted")
                && r.athlete_id && r.workout_object_id) {
                stmts.push(env.DB.prepare(
                    `UPDATE workouts
                     SET sui_object_id = ?, verified = 1
                     WHERE athlete_id = ? AND sui_tx_digest = ?`
                ).bind(r.workout_object_id, r.athlete_id, r.tx_digest));
            }
        }
        if (stmts.length) await env.DB.batch(stmts);
        ingested = rows.length;

        if (res.nextCursor) {
            await env.DB.prepare(
                `UPDATE schema_meta SET value = ?, updated_at = unixepoch()
                 WHERE key = 'sui_indexer_cursor'`
            ).bind(JSON.stringify(res.nextCursor)).run();
        }
        return { ok: true, ingested, cursor: JSON.stringify(res.nextCursor ?? cursor) };
    } catch (err) {
        return { ok: false, error: err instanceof Error ? err.message : "unknown" };
    }
}
