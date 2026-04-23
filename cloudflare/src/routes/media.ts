import { Hono } from "hono";
import type { Env, Variables } from "../env.js";
import { requireAthlete } from "../auth.js";

export const media = new Hono<{ Bindings: Env; Variables: Variables }>();

// Upload a file to R2. The iOS app PUTs the image bytes directly here with
// the session token; the Worker streams them into the bucket. Keeps media
// in the same origin as the API, which is simpler than presigning a URL.
media.put("/media/upload/:kind/:id", async (c) => {
    const me = requireAthlete(c);
    const kind = c.req.param("kind"); // "avatar" | "club" | "workout"
    const id = c.req.param("id");
    if (!["avatar", "club", "workout"].includes(kind)) {
        return c.json({ error: "bad_kind" }, 400);
    }
    const key = `${kind}/${id}/${Date.now()}.jpg`;
    const body = await c.req.arrayBuffer();
    if (body.byteLength > 5 * 1024 * 1024) {
        return c.json({ error: "too_large", maxBytes: 5 * 1024 * 1024 }, 413);
    }
    await c.env.MEDIA.put(key, body, {
        httpMetadata: {
            contentType: c.req.header("Content-Type") ?? "image/jpeg",
            cacheControl: "public, max-age=31536000, immutable",
        },
        customMetadata: { uploader: me, kind, subject: id },
    });
    // Point the owning row at the new key.
    if (kind === "avatar") {
        await c.env.DB.prepare(`UPDATE athletes SET photo_r2_key = ? WHERE id = ?`)
            .bind(key, id).run();
    } else if (kind === "club") {
        await c.env.DB.prepare(`UPDATE clubs SET banner_r2_key = ? WHERE id = ?`)
            .bind(key, id).run();
    }
    return c.json({ key, url: `/media/${key}` });
});

// Serve the image back. R2 is fronted through the Worker so we can lazily
// add caching/resizing/auth later. Long cache headers because keys are
// immutable (timestamped).
media.get("/media/*", async (c) => {
    const key = c.req.path.replace(/^\/media\//, "");
    const obj = await c.env.MEDIA.get(key);
    if (!obj) return c.json({ error: "not_found" }, 404);
    const headers = new Headers();
    obj.writeHttpMetadata(headers);
    headers.set("etag", obj.httpEtag);
    return new Response(obj.body, { headers });
});
