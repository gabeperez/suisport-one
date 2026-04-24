import { Hono } from "hono";
import type { Env, Variables } from "../env.js";
import { hasSuiConfig, suiClient, getSweatBalance, operatorAddress } from "../sui.js";
import { indexTick } from "../indexer.js";

export const sui = new Hono<{ Bindings: Env; Variables: Variables }>();

// GET /v1/sui/status
// Exposes enough to debug the on-chain pipeline at a glance: which
// network, whether the package is configured, operator address, latest
// indexer cursor, current chain epoch.
sui.get("/sui/status", async (c) => {
    const network = c.env.SUI_NETWORK || "testnet";
    const configured = hasSuiConfig(c.env);
    let epoch: string | null = null;
    if (configured) {
        try {
            const client = suiClient(c.env);
            const state = await client.getLatestSuiSystemState();
            epoch = state.epoch;
        } catch {
            epoch = null;
        }
    }
    const cursor = await c.env.DB.prepare(
        `SELECT value FROM schema_meta WHERE key = 'sui_indexer_cursor'`
    ).first<{ value: string }>();
    const net = network;
    const explorer = net === "mainnet" ? "https://suiscan.xyz/mainnet" : "https://suiscan.xyz/testnet";
    return c.json({
        network: net,
        configured,
        packageId: c.env.SUI_PACKAGE_ID ?? null,
        rewardsEngineId: c.env.SUI_REWARDS_ENGINE_ID ?? null,
        oracleCapId: c.env.SUI_ORACLE_CAP_ID ?? null,
        versionObjectId: c.env.SUI_VERSION_OBJECT_ID ?? null,
        operatorAddress: operatorAddress(c.env),
        walrusPublisher: c.env.WALRUS_PUBLISHER_URL ?? "https://publisher.walrus-testnet.walrus.space",
        walrusAggregator: c.env.WALRUS_AGGREGATOR_URL ?? "https://aggregator.walrus-testnet.walrus.space",
        epoch,
        indexerCursor: cursor?.value || null,
        explorerUrl: explorer,
    });
});

sui.get("/sui/balance/:address", async (c) => {
    const address = c.req.param("address");
    const balance = await getSweatBalance(c.env, address);
    // SWEAT has 9 decimals per sui::coin convention.
    const whole = Number(BigInt(balance) / 1_000_000_000n);
    const fraction = Number(BigInt(balance) % 1_000_000_000n);
    return c.json({
        address,
        raw: balance,
        display: `${whole}.${String(fraction).padStart(9, "0").replace(/0+$/, "") || "0"}`,
    });
});

// Manually trigger an indexer tick. Useful for debugging; also what the
// scheduled() handler calls behind the scenes.
sui.post("/sui/index", async (c) => {
    const result = await indexTick(c.env);
    return c.json(result);
});
