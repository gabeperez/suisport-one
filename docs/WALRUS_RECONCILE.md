# Walrus reconciler — spec

> **Status:** scoped, not built. Pick this up when ready.
>
> **Goal:** finish Option C — when Walrus testnet is flaky, workouts mint
> to chain immediately with a `walrus_pending_<id>` placeholder blob ID,
> then a background cron retries the upload and patches the on-chain
> Workout object's `walrus_blob_id` field once Walrus is healthy.

---

## What we shipped (Option A)

`cloudflare/src/routes/workouts.ts` — the chain mint no longer waits
on Walrus. If `walrusUploadSafe` returns no blob id, we pass a
placeholder string into `submit_workout`. Sui mints SWEAT + the
Workout NFT to the athlete regardless. iOS shows
`"Verified · proof archive syncing"` for that pipeline state.

| pipelineStatus | Meaning |
|---|---|
| `executed` | Sui mint + Walrus upload both landed. Real blob id on chain. |
| `executed_walrus_pending` | Sui mint landed; Walrus is still being retried. |
| `walrus_upload_failed` | (no longer fires — kept for back-compat) |
| `sui_failed:<reason>` | Sui mint threw. Walrus state irrelevant. |

## What's still missing

When `executed_walrus_pending` fires, the on-chain Workout object
carries a placeholder bytes value (`walrus_pending_<workoutId>`) in
its `walrus_blob_id` field. There's no automated path to:

1. Re-attempt the Walrus upload
2. Update the on-chain Workout to point at the real blob id

So today, a workout minted while Walrus was down is forever stuck
with a placeholder. The Sui mint is real, the SWEAT is real — but
the "permanent record" link doesn't resolve.

---

## What to build

### 1. Cloudflare Worker cron tick

Already have a scheduled `* * * * *` cron in `wrangler.toml`. Add a
new tick handler:

```typescript
// cloudflare/src/walrus_reconcile.ts (new file)
export async function reconcileWalrusPendingTick(env: Env) {
    const rows = await env.DB.prepare(
        `SELECT id, sui_tx_digest, athlete_id, /* canonical fields */
         FROM workouts
         WHERE walrus_blob_id LIKE 'walrus_pending_%'
            OR walrus_blob_id IS NULL
         ORDER BY created_at ASC
         LIMIT 25`
    ).all();

    for (const row of rows.results) {
        // 1. Rebuild the canonical workout JSON from the row
        const canonical = rebuildCanonical(row);
        // 2. Try Walrus upload again
        const result = await walrusUploadSafe(env, canonical);
        if (!result.blobId) continue;  // still down — try next tick
        // 3. Update D1 + emit a new on-chain "patch" event
        await env.DB.prepare(
            `UPDATE workouts SET walrus_blob_id = ? WHERE id = ?`
        ).bind(result.blobId, row.id).run();
        await patchWorkoutBlobOnChain(env, row.sui_tx_digest, result.blobId);
    }
}
```

Wire it from the existing `index.ts` scheduled handler.

### 2. Move contract: `patch_walrus_blob`

The current Workout struct has `walrus_blob_id: vector<u8>` but no
mutator. Add a package-internal entry that the operator can call to
update the field when the real blob lands:

```move
// workout_registry.move
public(package) fun patch_walrus_blob(
    workout: &mut Workout,
    new_blob_id: vector<u8>,
) {
    // Only allow patching when the existing value is a placeholder.
    // Prevents an operator from rewriting an already-correct record.
    let current = &workout.walrus_blob_id;
    let prefix = b"walrus_pending_";
    assert!(starts_with(current, &prefix), EAlreadyArchived);
    workout.walrus_blob_id = new_blob_id;

    event::emit(WorkoutBlobPatched {
        workout_id: object::id(workout),
        athlete: workout.athlete,
        new_blob_id,
    });
}
```

Plus a `rewards_engine` wrapper that looks up the workout by digest
+ verifies the operator is authorized.

### 3. iOS: refresh on patch

When the iOS app fetches `/v1/workouts/<id>/onchain` (the existing
endpoint used by the workout-detail proof link), the response can
now flip from `walrus_pending_…` to a real blob id at any time.
Cache invalidation: just refetch on appear; the response is small.

The "Verified · proof archive syncing" copy in
`UploadPastWorkoutsSheet` becomes ground truth — no copy change
needed; the row title flips to "Verified" once the workout's
`suiTxDigest` is on chain (already true today). Adding a small
"📦 archive synced" badge once the blob lands is polish.

---

## Edge cases

- **Walrus testnet stays down for hours.** Cron keeps retrying,
  pending count grows. No user impact — Sweat is already minted.
  Set a `LIMIT 25` per tick so we don't blow gas / Walrus quota.

- **Operator key rotated between mint and reconcile.** The patch
  call uses the operator that owns the original Workout's profile;
  store that hint in D1 if not already.

- **Race between two ticks.** The `LIKE 'walrus_pending_%'` filter +
  serial cron makes this unlikely, but the Move `assert` on
  placeholder prefix is the real safety net — patching an already-
  patched workout aborts.

- **Old workouts pre-A.** Workouts with `walrus_blob_id IS NULL`
  (because they were minted before A landed and Walrus failed) get
  picked up by the same cron. Same path.

---

## Implementation order

1. Move: add `patch_walrus_blob` + `WorkoutBlobPatched` event. Test
   on testnet via a one-shot call. ~30 min.
2. Worker: `reconcileWalrusPendingTick` + wire to scheduled
   handler. ~30 min.
3. Tighten the iOS workout-detail refetch to invalidate when the
   workout was minted in `walrus_pending` state. ~10 min (might be
   already covered).
4. Smoke test: kill Walrus locally (mock the publisher to 503), do
   a submit, see `executed_walrus_pending`, restore Walrus, watch
   the cron patch the blob, verify Suiscan shows the new event.
   ~20 min.

**Total: ~90 minutes.** Not for tomorrow's demo.

---

## Why this is "C" not "B"

The earlier conversation incorrectly described "B" as moving the
Workout NFT from the operator-owned profile to the user's wallet.
Re-reading `workout_registry.move:92` proves that's already how it
works:

```move
transfer::transfer(workout, athlete);  // key-only = soulbound
```

The user already owns their soulbound Workout NFT. So there's no
"B" to ship — the contract is right. The remaining gap is just the
Walrus reconciler.

---

## Suggested branch

`feat/walrus-reconcile`. Branch off main after the current polish
PR merges. Doesn't need to stack on anything.
