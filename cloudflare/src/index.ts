import { Hono } from "hono";
import { cors } from "hono/cors";
import type { Env, Variables } from "./env.js";
import { sessionMiddleware, rateLimit, attestMiddleware } from "./auth.js";
import { ValidationError } from "./validation.js";
import { social } from "./routes/social.js";
import { workouts } from "./routes/workouts.js";
import { media } from "./routes/media.js";
import { admin } from "./routes/admin.js";
import { auth } from "./routes/auth.js";
import { account } from "./routes/account.js";
import { attestation } from "./routes/attestation.js";
import { sui } from "./routes/sui.js";
import { indexTick } from "./indexer.js";
import { retryPendingWorkoutsTick } from "./onchain_retry.js";

const app = new Hono<{ Bindings: Env; Variables: Variables }>();

app.use("*", cors({
    origin: "*",
    allowHeaders: ["Authorization", "Content-Type", "X-Admin-Token"],
    allowMethods: ["GET", "POST", "PATCH", "DELETE", "PUT", "OPTIONS"],
    maxAge: 86_400,
}));
app.use("*", sessionMiddleware);

// Wallet-connect UI moved to a dedicated Cloudflare Pages project
// (cloudflare/wallet-bridge — Vite + React + @mysten/dapp-kit) so it
// can render ConnectButton with full Wallet Standard discovery. The
// Worker no longer serves wallet HTML inline.

app.get("/", (c) => c.json({
    service: "suisport-api",
    version: "0.1.0",
    environment: c.env.ENVIRONMENT,
    docs: "See /health for liveness, routes under /v1/*",
}));

app.get("/health", async (c) => {
    const row = await c.env.DB.prepare(
        "SELECT value FROM schema_meta WHERE key = 'demo_seeded'"
    ).first<{ value: string }>();
    return c.json({
        ok: true,
        ts: Date.now(),
        demoSeeded: row?.value === "1",
    });
});

// Mount everything under /v1 so future breaking changes can ship as /v2.
const v1 = new Hono<{ Bindings: Env; Variables: Variables }>();
// Rate-limit every mutating method. GET / HEAD / OPTIONS pass through
// so feed browsing stays snappy even under noisy clients.
// Rate-limit mutating routes. Registered before attestation so a flood
// of bogus attestation headers still gets dropped by the rate limiter
// before we spend cycles CBOR-decoding.
v1.use("*", async (c, next) => {
    if (c.req.method === "GET" || c.req.method === "HEAD" || c.req.method === "OPTIONS") {
        return next();
    }
    return rateLimit(c, next);
});
// Attestation gate after rate limiting. Hono runs each use() as its
// own middleware layer with its own next() call — keeping them
// separate means a 401 from either short-circuits cleanly.
v1.use("*", async (c, next) => {
    if (c.req.method === "GET" || c.req.method === "HEAD" || c.req.method === "OPTIONS") {
        return next();
    }
    return attestMiddleware(c, next);
});
v1.route("/", auth);
v1.route("/", account);
v1.route("/", attestation);
v1.route("/", sui);
v1.route("/", social);
v1.route("/workouts", workouts);
v1.route("/", media);
v1.route("/", admin);

app.route("/v1", v1);

app.notFound((c) => c.json({ error: "not_found", path: c.req.path }, 404));
app.onError((err, c) => {
    if (err instanceof ValidationError) {
        return c.json({ error: "validation_error", issues: err.issues }, 400);
    }
    if (err.message === "UNAUTHORIZED") {
        return c.json({ error: "unauthorized" }, 401);
    }
    console.error("unhandled error", err);
    return c.json({ error: "internal_error" }, 500);
});

// Scheduled: runs every minute (see wrangler.toml [triggers]). Does
// two things in parallel so a slow one doesn't starve the other:
//   1. indexTick        — poll Sui events into D1 (read path)
//   2. retryPendingWorkoutsTick — retry failed submit_workout calls
//                                  whose D1 row is stuck on
//                                  sui_tx_digest LIKE 'pending_%'
// Both no-op gracefully when SUI_* secrets aren't configured.
export default {
    fetch: app.fetch,
    async scheduled(
        _event: ScheduledEvent,
        env: Env,
        ctx: ExecutionContext
    ): Promise<void> {
        ctx.waitUntil(indexTick(env).then((r) => {
            if (!r.ok) console.warn("indexer tick skipped", r.error);
            else if ((r.ingested ?? 0) > 0) console.log(`indexed ${r.ingested} events`);
        }));
        ctx.waitUntil(retryPendingWorkoutsTick(env).then((r) => {
            if (r.succeeded > 0 || r.failed > 0) {
                console.log(`onchain_retry: succeeded=${r.succeeded} failed=${r.failed} attempted=${r.attempted}`);
            }
        }).catch((err) => {
            console.warn("onchain_retry tick failed", err);
        }));
    },
};
