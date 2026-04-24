// Walrus testnet HTTP client. The publisher accepts raw bytes and returns
// a blob id; the aggregator serves blobs back by id. Both speak plain HTTP
// so we don't need the Walrus SDK — we just fetch().
//
// Public testnet endpoints (as of 2026):
//   publisher:  https://publisher.walrus-testnet.walrus.space
//   aggregator: https://aggregator.walrus-testnet.walrus.space
//
// Override via env.WALRUS_PUBLISHER_URL / env.WALRUS_AGGREGATOR_URL if the
// public endpoints rate-limit or move.

const DEFAULT_PUBLISHER = "https://publisher.walrus-testnet.walrus.space";
const DEFAULT_AGGREGATOR = "https://aggregator.walrus-testnet.walrus.space";

export interface WalrusUploadResult {
    blobId: string;
    endEpoch: number;
    certified: boolean;
}

export interface WalrusEnv {
    WALRUS_PUBLISHER_URL?: string;
    WALRUS_AGGREGATOR_URL?: string;
}

/** Upload raw bytes to Walrus. Returns the blobId (base64 string). */
export async function walrusUpload(
    env: WalrusEnv,
    bytes: Uint8Array,
    epochs = 5
): Promise<WalrusUploadResult> {
    const publisher = env.WALRUS_PUBLISHER_URL || DEFAULT_PUBLISHER;
    const url = `${publisher}/v1/blobs?epochs=${epochs}`;
    const res = await fetch(url, {
        method: "PUT",
        body: bytes as BodyInit,
        headers: { "Content-Type": "application/octet-stream" },
    });
    if (!res.ok) {
        throw new Error(`walrus_upload_failed: ${res.status} ${await res.text().catch(() => "")}`);
    }
    const data = await res.json<{
        newlyCreated?: { blobObject: { blobId: string; endEpoch: number }; resourceOperation?: unknown };
        alreadyCertified?: { blobId: string; endEpoch: number };
    }>();
    if (data.newlyCreated) {
        return {
            blobId: data.newlyCreated.blobObject.blobId,
            endEpoch: data.newlyCreated.blobObject.endEpoch,
            certified: false,
        };
    }
    if (data.alreadyCertified) {
        return {
            blobId: data.alreadyCertified.blobId,
            endEpoch: data.alreadyCertified.endEpoch,
            certified: true,
        };
    }
    throw new Error("walrus_upload_unexpected_response");
}

/** Download bytes by blobId. Used for replay-from-storage + verification. */
export async function walrusDownload(
    env: WalrusEnv,
    blobId: string
): Promise<Uint8Array> {
    const aggregator = env.WALRUS_AGGREGATOR_URL || DEFAULT_AGGREGATOR;
    const url = `${aggregator}/v1/blobs/${blobId}`;
    const res = await fetch(url);
    if (!res.ok) {
        throw new Error(`walrus_download_failed: ${res.status}`);
    }
    return new Uint8Array(await res.arrayBuffer());
}

/** Non-throwing upload for use in the workout pipeline — pipeline keeps
 *  going with a null blob id if Walrus is unreachable.
 *
 *  Retries up to 3 times with backoff [500ms, 1500ms, 3500ms]. Walrus
 *  publishers occasionally 502/503 under load and the retry typically
 *  succeeds within a few seconds. The total worst case is ~5.5s added
 *  latency on a doomed upload — callers (workouts.ts) already respond
 *  from D1 first so the user doesn't feel this in practice. */
export async function walrusUploadSafe(
    env: WalrusEnv,
    bytes: Uint8Array
): Promise<{ blobId: string | null; error?: string }> {
    // Attempt N: delay before this attempt. The 0-index element is 0
    // because the first attempt is immediate.
    const delaysMs = [0, 500, 1500, 3500];
    let lastErr: unknown = null;
    for (let attempt = 0; attempt < delaysMs.length; attempt++) {
        if (delaysMs[attempt] > 0) {
            await new Promise((r) => setTimeout(r, delaysMs[attempt]));
        }
        try {
            const res = await walrusUpload(env, bytes);
            return { blobId: res.blobId };
        } catch (err) {
            lastErr = err;
        }
    }
    return {
        blobId: null,
        error: lastErr instanceof Error ? lastErr.message : "unknown",
    };
}
