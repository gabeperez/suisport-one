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
import { walletBridge } from "./routes/walletBridge.js";
import { indexTick } from "./indexer.js";

const app = new Hono<{ Bindings: Env; Variables: Variables }>();

app.use("*", cors({
    origin: "*",
    allowHeaders: ["Authorization", "Content-Type", "X-Admin-Token"],
    allowMethods: ["GET", "POST", "PATCH", "DELETE", "PUT", "OPTIONS"],
    maxAge: 86_400,
}));
app.use("*", sessionMiddleware);

// Wallet-connect HTML lives at the root (no /v1 prefix) so
// ASWebAuthenticationSession can open a short URL like
// https://suisport-api.../wallet-connect?challengeId=...
app.route("/", walletBridge);

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

// Scheduled: Sui event indexer tick. Wired up in wrangler.toml's
// [triggers] block. A no-op when SUI_* secrets aren't configured.
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
    },
};
