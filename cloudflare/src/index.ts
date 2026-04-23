import { Hono } from "hono";
import { cors } from "hono/cors";
import type { Env, Variables } from "./env.js";
import { sessionMiddleware } from "./auth.js";
import { social } from "./routes/social.js";
import { workouts } from "./routes/workouts.js";
import { media } from "./routes/media.js";
import { admin } from "./routes/admin.js";
import { auth } from "./routes/auth.js";

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
v1.route("/", auth);
v1.route("/", social);
v1.route("/workouts", workouts);
v1.route("/", media);
v1.route("/", admin);

app.route("/v1", v1);

app.notFound((c) => c.json({ error: "not_found", path: c.req.path }, 404));
app.onError((err, c) => {
    const msg = err.message === "UNAUTHORIZED" ? "unauthorized" : err.message;
    const status = err.message === "UNAUTHORIZED" ? 401 : 500;
    return c.json({ error: msg }, status);
});

export default app;
