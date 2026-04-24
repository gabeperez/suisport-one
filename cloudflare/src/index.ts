import { Hono } from "hono";
import { cors } from "hono/cors";
import type { Env, Variables } from "./env.js";
import { sessionMiddleware, rateLimit } from "./auth.js";
import { ValidationError } from "./validation.js";
import { social } from "./routes/social.js";
import { workouts } from "./routes/workouts.js";
import { media } from "./routes/media.js";
import { admin } from "./routes/admin.js";
import { auth } from "./routes/auth.js";
import { account } from "./routes/account.js";
import { attestation } from "./routes/attestation.js";

const app = new Hono<{ Bindings: Env; Variables: Variables }>();

app.use("*", cors({
    origin: "*",
    allowHeaders: ["Authorization", "Content-Type", "X-Admin-Token"],
    allowMethods: ["GET", "POST", "PATCH", "DELETE", "PUT", "OPTIONS"],
    maxAge: 86_400,
}));
app.use("*", sessionMiddleware);

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
v1.use("*", async (c, next) => {
    if (c.req.method === "GET" || c.req.method === "HEAD" || c.req.method === "OPTIONS") {
        return next();
    }
    return rateLimit(c, next);
});
v1.route("/", auth);
v1.route("/", account);
v1.route("/", attestation);
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

export default app;
