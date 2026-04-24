import { Hono } from "hono";
import type { Env, Variables } from "../env.js";
import { requireAthlete } from "../auth.js";

export const media = new Hono<{ Bindings: Env; Variables: Variables }>();

const MAX_IMAGE_BYTES = 5 * 1024 * 1024;

const ALLOWED_IMAGE_MIME: Record<string, string> = {
    "image/jpeg": "jpg",
    "image/jpg":  "jpg",
    "image/png":  "png",
    "image/webp": "webp",
};

/// Extract a clean mime + extension from a Content-Type header. Returns
/// null when the mime isn't in our whitelist.
function pickImageExt(mime: string | null | undefined): string | null {
    if (!mime) return null;
    const base = mime.split(";")[0].trim().toLowerCase();
    return ALLOWED_IMAGE_MIME[base] ?? null;
}

/// POST /v1/media/avatar
///
/// Two accepted call shapes:
///   a) multipart/form-data with field "image"
///   b) raw body with Content-Type: image/jpeg | image/png | image/webp
///
/// Always stores under `avatars/<athleteId>/<uuid>.<ext>` in R2.
/// Returns { url, r2Key } — the client then PATCH /me with
/// `avatarR2Key` to pin the uploaded image to the profile. This split
/// (upload then patch) lets the UI preview a new avatar without
/// committing it, and leaves orphan blobs that a janitor job can GC.
media.post("/media/avatar", async (c) => {
    const me = requireAthlete(c);

    let bytes: Uint8Array | null = null;
    let ext: string | null = null;
    let mimeOut = "image/jpeg";

    const ct = c.req.header("Content-Type") ?? "";
    if (ct.toLowerCase().startsWith("multipart/form-data")) {
        // Hono wraps the standard FormData API; the "image" field is
        // required. We duck-type rather than use `instanceof File`
        // because the Workers global `File` isn't in @cloudflare/
        // workers-types' ambient globals (it's spec'd but unexposed
        // in older type bundles). `arrayBuffer()` + `type` + `size`
        // are what we actually need to read.
        const form = await c.req.formData().catch(() => null);
        const raw = form?.get("image");
        const f = raw as unknown as {
            type?: string; size?: number;
            arrayBuffer?: () => Promise<ArrayBuffer>;
        } | null;
        if (!f || typeof f.arrayBuffer !== "function") {
            return c.json({ error: "missing_image_field" }, 400);
        }
        if ((f.size ?? 0) > MAX_IMAGE_BYTES) {
            return c.json({ error: "too_large", maxBytes: MAX_IMAGE_BYTES }, 400);
        }
        ext = pickImageExt(f.type);
        if (!ext) return c.json({ error: "bad_mime", accepted: Object.keys(ALLOWED_IMAGE_MIME) }, 400);
        mimeOut = (f.type ?? "").split(";")[0].trim().toLowerCase();
        bytes = new Uint8Array(await f.arrayBuffer());
    } else {
        ext = pickImageExt(ct);
        if (!ext) {
            return c.json({ error: "bad_mime", accepted: Object.keys(ALLOWED_IMAGE_MIME) }, 400);
        }
        mimeOut = ct.split(";")[0].trim().toLowerCase();
        const buf = await c.req.arrayBuffer();
        if (buf.byteLength > MAX_IMAGE_BYTES) {
            return c.json({ error: "too_large", maxBytes: MAX_IMAGE_BYTES }, 400);
        }
        bytes = new Uint8Array(buf);
    }

    if (!bytes || bytes.byteLength === 0) {
        return c.json({ error: "empty_body" }, 400);
    }

    const key = `avatars/${me}/${crypto.randomUUID()}.${ext}`;
    await c.env.MEDIA.put(key, bytes, {
        httpMetadata: {
            contentType: mimeOut,
            cacheControl: "public, max-age=31536000, immutable",
        },
        customMetadata: { uploader: me, kind: "avatar", subject: me },
    });

    return c.json({ url: `/media/${key}`, r2Key: key });
});

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
