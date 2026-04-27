// Rewards catalog + redemption.
//
// Off-chain MVP: user spends Sweat Points from `sweat_points.total` for
// a pre-generated code (promo codes, gift cards, etc.). The ledger is
// D1; no on-chain burn yet. A follow-up will add an on-chain Redemption
// event + $SWEAT burn so the spend is auditable, but for testnet the
// server-side accounting is sufficient and testable end-to-end.
//
// Admin endpoints for managing the catalog live in admin.ts — this
// file is the user-facing surface only.

import { Hono } from "hono";
import { z } from "zod";
import type { Env, Variables } from "../env.js";
import { requireAthlete } from "../auth.js";
import { parseBody } from "../validation.js";
import { sponsorSuiTransfer } from "../sui.js";

export const rewards = new Hono<{ Bindings: Env; Variables: Variables }>();

/// Sample-redemption nominal cost + payout. 1 Sweat off-chain unlocks a
/// 0.001 SUI sponsored transfer from operator → user. The on-chain
/// footprint is the demo proof-point — it shows judges that the
/// redemption path connects to Sui without requiring a Move upgrade.
const SAMPLE_REDEEM_COST = 1;
const SAMPLE_REDEEM_PAYOUT_MIST = 1_000_000n; // 0.001 SUI

// Public catalog — no auth required (the iOS app shows it before the
// user signs up too, as a "what can I earn" preview). Only returns
// active items that still have stock.
rewards.get("/rewards/catalog", async (c) => {
    const rows = await c.env.DB.prepare(
        `SELECT id, sku, title, subtitle, description, image_url,
                cost_points, stock_total, stock_claimed
         FROM rewards_catalog
         WHERE active = 1 AND (stock_total = 0 OR stock_claimed < stock_total)
         ORDER BY cost_points ASC`
    ).all<{
        id: string; sku: string; title: string; subtitle: string | null;
        description: string | null; image_url: string | null;
        cost_points: number; stock_total: number; stock_claimed: number;
    }>();
    return c.json({
        items: (rows.results ?? []).map(r => ({
            id: r.id,
            sku: r.sku,
            title: r.title,
            subtitle: r.subtitle,
            description: r.description,
            imageUrl: r.image_url,
            costPoints: r.cost_points,
            stockRemaining: r.stock_total === 0 ? null : (r.stock_total - r.stock_claimed),
        })),
    });
});

const RedeemSchema = z.object({
    catalogId: z.string().min(1).max(64),
});

rewards.post("/rewards/redeem", async (c) => {
    const athleteId = requireAthlete(c);
    const { catalogId } = await parseBody(c, RedeemSchema);

    // Read catalog row + user balance atomically-ish. D1 doesn't
    // offer transactions across prepare calls, but we guard against
    // double-redeem by using a conditional UPDATE on sweat_points
    // (spend fails if balance dropped below cost in the meantime).
    const item = await c.env.DB.prepare(
        `SELECT id, cost_points, code_pool, stock_total, stock_claimed, active
         FROM rewards_catalog WHERE id = ?`
    ).bind(catalogId).first<{
        id: string; cost_points: number; code_pool: string;
        stock_total: number; stock_claimed: number; active: number;
    }>();
    if (!item) return c.json({ error: "not_found" }, 404);
    if (item.active === 0) return c.json({ error: "inactive" }, 410);
    if (item.stock_total > 0 && item.stock_claimed >= item.stock_total) {
        return c.json({ error: "out_of_stock" }, 410);
    }

    // Pop the first line from code_pool atomically — substr() + instr()
    // keeps it as a single UPDATE instead of read-modify-write.
    // Returns NULL from `changes` if the pool was already empty.
    const popped = await c.env.DB.prepare(
        `UPDATE rewards_catalog
         SET code_pool = CASE
               WHEN instr(code_pool, x'0a') > 0
                 THEN substr(code_pool, instr(code_pool, x'0a') + 1)
               ELSE ''
             END,
             stock_claimed = stock_claimed + 1
         WHERE id = ? AND code_pool != ''
         RETURNING CASE
           WHEN instr(code_pool, x'0a') > 0
             THEN substr(code_pool, 1, instr(code_pool, x'0a') - 1)
           ELSE code_pool
         END AS code`
    ).bind(catalogId).first<{ code: string }>();
    if (!popped?.code) return c.json({ error: "out_of_stock" }, 410);

    // Spend points — conditional on having enough. If this fails,
    // we have a lost code. Recover by pushing it back to the pool.
    const spend = await c.env.DB.prepare(
        `UPDATE sweat_points
         SET total = total - ?
         WHERE athlete_id = ? AND total >= ?`
    ).bind(item.cost_points, athleteId, item.cost_points).run();

    if ((spend.meta.changes ?? 0) === 0) {
        // Spend failed (insufficient points or race). Try to put the
        // popped code back into the pool + roll back the stock claim
        // bump. If that refund UPDATE ALSO fails, we log to
        // redemption_refunds as a last-resort recovery record so an
        // operator can credit the user manually. We never want to
        // return the code to the user since we already decided to
        // 402 — they'd have the string but no D1 row linking them.
        try {
            const refund = await c.env.DB.prepare(
                `UPDATE rewards_catalog
                 SET code_pool = ? || CASE WHEN code_pool = '' THEN '' ELSE x'0a' END || code_pool,
                     stock_claimed = stock_claimed - 1
                 WHERE id = ?`
            ).bind(popped.code, catalogId).run();
            if ((refund.meta.changes ?? 0) === 0) {
                await logLostCode(c.env, athleteId, catalogId, popped.code, "refund_update_zero_rows");
            }
        } catch (err) {
            await logLostCode(
                c.env, athleteId, catalogId, popped.code,
                err instanceof Error ? err.message : "refund_failed"
            );
        }
        return c.json({ error: "insufficient_points" }, 402);
    }

    // Redemption ledger — isolated from the spend/pop so a unique
    // constraint collision (extremely unlikely with randomUUID) can
    // be surfaced without corrupting sweat_points state.
    const redemptionId = `rd_${crypto.randomUUID().replace(/-/g, "").slice(0, 16)}`;
    try {
        await c.env.DB.prepare(
            `INSERT INTO redemptions (id, athlete_id, catalog_id, cost_points, code_revealed)
             VALUES (?, ?, ?, ?, ?)`
        ).bind(redemptionId, athleteId, catalogId, item.cost_points, popped.code).run();
    } catch (err) {
        // If the redemption log INSERT fails we still hand the code
        // back to the user (we already debited their points + the
        // code is consumed) but log it as a reconciliation breadcrumb
        // so support can reconstruct history.
        await logLostCode(
            c.env, athleteId, catalogId, popped.code,
            `redemption_insert_failed: ${err instanceof Error ? err.message : "unknown"}`
        );
    }

    return c.json({
        redemptionId,
        code: popped.code,
        costPoints: item.cost_points,
    });
});

// Sample on-chain redemption — spends 1 Sweat off-chain, sponsors a
// tiny SUI transfer back to the user's wallet. This is the demo's
// "redemption connects to Sui" moment without touching the Move package.
//
// Failure semantics: if the on-chain transfer throws after we already
// debited the user, we credit the point back. We surface the original
// chain error to the client so the iOS UI can show a useful message.
rewards.post("/rewards/redeem-sample", async (c) => {
    const athleteId = requireAthlete(c);

    // Athlete id IS the Sui address for zkLogin / wallet users (set by
    // requireAthlete from the session row). Demo athleteIds start with
    // "0xdemo_" and don't have a real address — reject those.
    const isRealAddress =
        athleteId.startsWith("0x") && athleteId.length === 66;
    if (!isRealAddress) {
        return c.json({
            error: "no_wallet",
            message: "Sample redemption needs a real Sui address. Sign in with Apple, Google, or a wallet.",
        }, 400);
    }

    // Spend 1 Sweat conditionally.
    const spend = await c.env.DB.prepare(
        `UPDATE sweat_points SET total = total - ?
         WHERE athlete_id = ? AND total >= ?`
    ).bind(SAMPLE_REDEEM_COST, athleteId, SAMPLE_REDEEM_COST).run();
    if ((spend.meta.changes ?? 0) === 0) {
        return c.json({ error: "insufficient_points" }, 402);
    }

    // Sponsor the on-chain receipt.
    let txDigest: string;
    try {
        const res = await sponsorSuiTransfer(
            c.env,
            athleteId,
            SAMPLE_REDEEM_PAYOUT_MIST,
        );
        txDigest = res.txDigest;
    } catch (err) {
        // Refund the Sweat we just spent — we never want a user to lose
        // a point with no on-chain receipt.
        await c.env.DB.prepare(
            `UPDATE sweat_points SET total = total + ?
             WHERE athlete_id = ?`
        ).bind(SAMPLE_REDEEM_COST, athleteId).run();
        return c.json({
            error: "onchain_failed",
            message: err instanceof Error ? err.message : "unknown",
        }, 502);
    }

    const explorerBase = c.env.SUI_NETWORK === "mainnet"
        ? "https://suiscan.xyz/mainnet"
        : "https://suiscan.xyz/testnet";

    return c.json({
        redemptionId: `rd_sample_${crypto.randomUUID().replace(/-/g, "").slice(0, 16)}`,
        costPoints: SAMPLE_REDEEM_COST,
        suiAmountMist: SAMPLE_REDEEM_PAYOUT_MIST.toString(),
        suiAmountDisplay: "0.001",
        txDigest,
        txExplorerUrl: `${explorerBase}/tx/${txDigest}`,
        walletExplorerUrl: `${explorerBase}/account/${athleteId}`,
        message: "This is a sample redemption for SuiSport ONE utilizing Sui. Real prizes will burn Sweat on mainnet.",
    });
});

rewards.get("/rewards/history", async (c) => {
    const athleteId = requireAthlete(c);
    const rows = await c.env.DB.prepare(
        `SELECT r.id, r.code_revealed, r.cost_points, r.redeemed_at,
                c.title, c.sku, c.image_url
         FROM redemptions r
         JOIN rewards_catalog c ON c.id = r.catalog_id
         WHERE r.athlete_id = ?
         ORDER BY r.redeemed_at DESC
         LIMIT 100`
    ).bind(athleteId).all<{
        id: string; code_revealed: string; cost_points: number;
        redeemed_at: number; title: string; sku: string;
        image_url: string | null;
    }>();
    return c.json({
        items: (rows.results ?? []).map(r => ({
            id: r.id,
            code: r.code_revealed,
            costPoints: r.cost_points,
            redeemedAt: r.redeemed_at,
            title: r.title,
            sku: r.sku,
            imageUrl: r.image_url,
        })),
    });
});

/// Best-effort ledger of redemption codes that escaped the normal flow
/// (refund UPDATE failed / redemption INSERT failed). Support reads
/// this table to figure out who to credit. Silent on write failure —
/// nothing we can usefully do if D1 itself is down.
async function logLostCode(
    env: Env,
    athleteId: string,
    catalogId: string,
    code: string,
    reason: string
): Promise<void> {
    try {
        await env.DB.prepare(
            `INSERT INTO redemption_refunds (id, athlete_id, catalog_id, code, reason)
             VALUES (?, ?, ?, ?, ?)`
        ).bind(
            `rf_${crypto.randomUUID().replace(/-/g, "").slice(0, 16)}`,
            athleteId, catalogId, code, reason.slice(0, 500)
        ).run();
    } catch {
        // Last-resort log — surface to stderr and move on.
        console.error("redemption_refund_log_failed", { athleteId, catalogId, reason });
    }
}
