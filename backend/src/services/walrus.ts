import { config } from "../config.js";

type UploadOpts = { ownerAddress: string; epochs?: number; deletable?: boolean };

/**
 * Upload a (pre-encrypted) blob to Walrus via a Publisher. The `send_object_to`
 * query parameter transfers the resulting Blob object to the user — so the
 * user OWNS the storage on-chain, even though our WAL treasury paid for it.
 *
 * For cost efficiency batch these into a per-user monthly Quilt via
 * `@mysten/walrus` `writeFilesFlow`. This function is the single-blob path;
 * the quilt implementation lands next.
 */
export async function uploadToWalrus(b64: string, opts: UploadOpts): Promise<string> {
  const body = Buffer.from(b64, "base64");
  const epochs = opts.epochs ?? 26;
  const deletable = opts.deletable ?? true;

  const url = new URL(`${config.walrus.publisherUrl}/v1/blobs`);
  url.searchParams.set("epochs", String(epochs));
  url.searchParams.set("send_object_to", opts.ownerAddress);
  if (deletable) url.searchParams.set("deletable", "true");

  const res = await fetch(url, { method: "PUT", body });
  if (!res.ok) throw new Error(`walrus: ${res.status} ${await res.text()}`);
  const json = await res.json() as {
    newlyCreated?: { blobObject: { blobId: string } };
    alreadyCertified?: { blobId: string };
  };
  const id = json.newlyCreated?.blobObject.blobId ?? json.alreadyCertified?.blobId;
  if (!id) throw new Error("walrus: missing blobId in response");
  return id;
}
