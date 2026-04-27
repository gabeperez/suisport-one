# Walrus reconciler — V2 (on-chain patch)

> **Status:** spec'd, not built.
>
> The lite (D1-only) reconciler ships in `cloudflare/src/walrus_reconcile.ts`
> and runs every minute via the scheduled handler. It patches D1's
> `walrus_blob_id` so the iOS "Permanent record" deep link starts
> resolving once Walrus recovers — no redeploy needed, no Move change.
>
> This doc is the **V2 step**: also patch the on-chain Workout NFT's
> `walrus_blob_id` field so anyone reading the chain object directly
> sees the real blob id (instead of a `walrus_pending_<id>` placeholder).

---

## What's already shipped (lite reconciler)

`cloudflare/src/routes/workouts.ts`: chain mint runs whenever Sui is
configured. If Walrus succeeds, real blob id goes on chain. If
Walrus fails, a `walrus_pending_<workoutId>` placeholder goes on
chain — Sweat + Workout NFT still land in the user's wallet.

`cloudflare/src/walrus_reconcile.ts`: cron tick that scans D1 for
chain-verified workouts with `walrus_blob_id IS NULL`, retries the
upload, and patches D1 on success. iOS reads the workout DTO from
D1, so the "Permanent record" deep link starts resolving on the
next refresh.

| pipelineStatus | Meaning | iOS row label |
|---|---|---|
| `executed` | Sui + Walrus both landed | "Verified." |
| `executed_walrus_pending` | Sui landed; Walrus retried by cron | "Verified · proof archive syncing" |
| `sui_failed:<reason>` | Sui throw | "Saved — chain step: <reason>" |

## The gap V2 closes

After the lite reconciler runs:
- D1's `walrus_blob_id` → real id ✅
- iOS's "Permanent record" link → resolves ✅
- The on-chain Workout NFT's `walrus_blob_id` field → still says `walrus_pending_<workoutId>` ❌

So if a third party (auditor, bridge, indexer) reads the on-chain
Workout directly, they see the placeholder forever. For tomorrow's
demo this is fine — judges click the iOS link, not raw Suiscan
struct fields. For a real product, the on-chain field should be
ground truth.

---

## V2 implementation

### Move contract: `patch_walrus_blob`

Add to `move/suisport/sources/workout_registry.move`:

```move
const EAlreadyArchived: u64 = 1;

public struct WorkoutBlobPatched has copy, drop {
    workout_id: ID,
    athlete: address,
    new_blob_id: vector<u8>,
}

/// Operator-only: replace a placeholder Walrus blob id with the real
/// one once the upload finally lands. Aborts if the workout already
/// has a non-placeholder id, so the operator can't rewrite history.
public fun patch_walrus_blob(
    _admin: &AdminCap,
    workout: &mut Workout,
    new_blob_id: vector<u8>,
) {
    let prefix = b"walrus_pending_";
    assert!(starts_with(&workout.walrus_blob_id, &prefix), EAlreadyArchived);
    workout.walrus_blob_id = new_blob_id;

    event::emit(WorkoutBlobPatched {
        workout_id: object::id(workout),
        athlete: workout.athlete,
        new_blob_id,
    });
}

fun starts_with(haystack: &vector<u8>, prefix: &vector<u8>): bool { ... }
```

This requires:
- `AdminCap` gating (operator must hold it, which it already does)
- Package upgrade via `UpgradeCap` (we have it from the original deploy)
- Update wrangler secret with the new package id

### Worker: extend the existing reconciler

In `walrus_reconcile.ts`, after the D1 update succeeds, call a new
on-chain helper:

```typescript
import { patchWorkoutBlobOnChain } from "./sui.js";

// inside the for-loop, after the D1 UPDATE:
try {
    await patchWorkoutBlobOnChain(env, {
        workoutOnChainId: <look-up-from-D1>,
        newBlobId: upload.blobId,
    });
} catch (err) {
    console.warn("walrus_reconcile.on_chain_patch_failed", err);
    // D1 is already updated; user-visible state is correct.
    // Retry on next tick.
}
```

Need a column or join to resolve workout id → on-chain Workout
object id. The submit_workout tx returns the Workout's `ID` in
`onChain.eventDigests`. We can either:
- Persist that in D1 (`workouts.sui_object_id`) at submit time. The
  schema already has the column based on `db.ts`'s WorkoutRow.
  Wire it through.
- OR query Suiscan to find the Workout object by tx digest. Slower.

Persist-at-submit is the right path.

### sui.ts: `patchWorkoutBlobOnChain`

```typescript
export async function patchWorkoutBlobOnChain(
    env: SuiEnv,
    input: { workoutOnChainId: string; newBlobId: string }
): Promise<{ txDigest: string }> {
    const operator = operatorKeypair(operatorKeyPool(env)[0]);
    const client = suiClient(env);
    const tx = new Transaction();
    tx.moveCall({
        target: `${env.SUI_PACKAGE_ID}::workout_registry::patch_walrus_blob`,
        arguments: [
            tx.object(env.SUI_ADMIN_CAP_ID!),
            tx.object(input.workoutOnChainId),
            tx.pure.vector("u8", Array.from(new TextEncoder().encode(input.newBlobId))),
        ],
    });
    const res = await client.signAndExecuteTransaction({
        signer: operator, transaction: tx, options: { showEffects: true },
    });
    return { txDigest: res.digest };
}
```

---

## Implementation order

1. **Move:** add `patch_walrus_blob` + `WorkoutBlobPatched` event.
   Run `sui move build` clean. ~25 min.
2. **Move:** package upgrade with the existing `UpgradeCap`.
   Update `wrangler secret put SUI_PACKAGE_ID` to the upgraded id.
   ~15 min + test. **Risk:** UpgradeCap could have been transferred
   away during testing — verify ownership first.
3. **Worker schema:** wire `workouts.sui_object_id` so the reconciler
   can resolve the Workout object id from a workoutId. ~10 min.
4. **Worker `sui.ts`:** add `patchWorkoutBlobOnChain` helper. ~10 min.
5. **Worker `walrus_reconcile.ts`:** call `patchWorkoutBlobOnChain`
   after each successful D1 update. ~5 min.
6. **Smoke test:** kill Walrus locally (mock 503), submit, see
   `executed_walrus_pending`, restore Walrus, watch the cron patch
   D1 + chain on the next tick. Verify Suiscan shows the new
   `WorkoutBlobPatched` event on the package. ~15 min.

**Total: ~80 minutes.** Not for tomorrow.

---

## Why this is a "real product" concern

The lite reconciler covers iOS users, who are 100% of the demo
audience. The V2 step covers:

- **Third-party indexers** that watch the package events directly
  and want a complete view of every workout's blob id over time
- **Audit trails** where someone needs to verify "this workout's
  canonical record matches the on-chain hash" without trusting D1
- **Data portability** if SuiSport ONE's worker goes away — the
  on-chain Workout object should resolve on Walrus standalone

For the hackathon and the v1 product, none of those audiences exist
yet. Lite is enough.

---

## Suggested branch

`feat/walrus-on-chain-patch`. Branch off main after the polish PR
merges. Stack on a stable mainnet deploy if going to production.
