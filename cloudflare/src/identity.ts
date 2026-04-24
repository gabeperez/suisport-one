// Translation between the public user_id (UUID the client uses) and
// the internal athletes.id (the Sui address FKs point to). Isolating
// this here keeps the rest of the code from caring about the dual
// identity — routes that take a path-param `:id` resolve it once at
// the API boundary.

import type { Env } from "./env.js";

/** Resolve any client-supplied athlete identifier (user_id UUID,
 *  sui_address, or the `0xdemo_*` seed ids) to the internal
 *  athletes.id used as FK everywhere. Returns null when unknown. */
export async function resolveInternalId(
    env: Env,
    publicId: string
): Promise<string | null> {
    if (!publicId) return null;
    // Existing schema: athletes.id already IS the sui address OR the
    // demo seed id. So the fast path is "if this looks like an internal
    // id, return it". user_id (hex-16 = 32 hex chars, no 0x prefix)
    // requires a DB lookup.
    if (publicId.startsWith("0x")) return publicId;
    const row = await env.DB.prepare(
        `SELECT id FROM athletes WHERE user_id = ?`
    ).bind(publicId).first<{ id: string }>();
    return row?.id ?? null;
}

/** Inverse: from the internal id (sui address) to the public UUID. */
export async function getPublicId(
    env: Env,
    internalId: string
): Promise<string | null> {
    const row = await env.DB.prepare(
        `SELECT user_id FROM athletes WHERE id = ?`
    ).bind(internalId).first<{ user_id: string }>();
    return row?.user_id ?? null;
}
