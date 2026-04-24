# On-chain write strategy

## Today's flow

Every workout submission fans out through this pipeline in `POST /v1/workouts`:

```
iOS ──► Worker ──► D1 (INSERT)
                ──► R2 (thumbnails, optional)
                ──► Walrus (canonical workout JSON → blobId)
                ──► Sui: ensureUserProfile(athleteId)    ── mints UserProfile if new
                ──► Sui: rewards_engine::submit_workout  ── emits WorkoutSubmitted + RewardMinted
                ──► D1 UPDATE (sui_tx_digest, sweat_minted, verified=1)
```

All on-chain calls are signed by one `SUI_OPERATOR_KEY` Ed25519 keypair that pays gas and owns every `UserProfile`. A separate `ORACLE_PRIVATE_KEY` signs an attestation digest that the Move contract verifies — the oracle never holds SUI.

A scheduled cron (`[triggers] crons = ["* * * * *"]` in `wrangler.toml`) runs two jobs every minute:
- `indexTick` — polls `queryEvents` for `WorkoutSubmitted` + `RewardMinted`, writes into D1 for feed queries.
- `retryPendingWorkoutsTick` — (new) scans workouts with `sui_tx_digest LIKE 'pending_%'` and retries `submit_workout` with exponential backoff (up to 10 attempts, ~2h effective ceiling).

## What works well

- **D1 is the source of truth for the UI**, so a failed on-chain submit never looks like a missing workout to the user.
- **Oracle ≠ operator**, so an oracle-key compromise can't drain the operator's SUI, and vice versa.
- **Rewards minting is deterministic** per (athlete, timestamp, blobId) tuple — the Move contract rejects replays via its own on-chain seen-digest map.
- **Indexer-driven verification** means the feed shows the on-chain truth, not whatever the Worker happened to claim.

## Risks and their fixes

### Risk 1 — Single-operator bottleneck
**What:** Every `submit_workout` is a sequential tx from one keypair. Sui caps a single signer at ~1 tx/sec reliably (shared-object contention on `RewardsEngine` + `Version`).

**When it bites:** >60 submissions/min across all users. Low on testnet, inevitable on mainnet at scale.

**Fixes in increasing cost:**
1. **Multi-operator round-robin.** `SUI_OPERATOR_KEYS` as comma-separated. Pick `keys[hash(athleteId) % N]`. Each key owns its users' profiles. Linear throughput scaling.
2. **Sponsored transactions.** User's zkLogin address signs, operator sponsors gas. Decouples signing from gas. 2x RPC round-trips but true horizontal scale.
3. **PTB batching in the reconciler.** Aggregate multiple `submit_workout` calls in one PTB. Limited by shared-object contention on `RewardsEngine`, but helpful for backlog drain.

Recommend (1) as the first lift — ~50 lines in `sui.ts`, zero contract changes, 10x capacity.

### Risk 2 — Operator-key compromise
**What:** `SUI_OPERATOR_KEY` in wrangler secrets. A leak lets the attacker mint arbitrary SWEAT.

**Mitigations already in contract:**
- `OracleCap` guards the attestation check — forging a submission still requires `ORACLE_PRIVATE_KEY` too.
- `submit_workout` verifies the digest over athlete/timestamp/blobId, so the attacker can't mint to themselves without knowing the oracle key.

**Open gap:** both keys live in the same Cloudflare account. A full-account compromise (which is a realistic single point of failure) hands over both. For testnet this is fine; for mainnet, consider:
- Move oracle signing to a Worker in a second account, fronted by service-bound auth.
- Use a hardware-backed KMS (AWS KMS custom keystore, Turnkey, Cubist) for the oracle key so the Worker signs via API instead of holding the seed.

### Risk 3 — Orphaned writes
**What:** Worker crashes between `D1 INSERT` and `rewards_engine::submit_workout`. Previously: workout sat forever with `sui_tx_digest = 'pending_<id>'` and nothing retried.

**Fix (shipped in this change):** `retryPendingWorkoutsTick` reconciler. Enqueues stuck workouts, backoffs, caps retries, logs the last error in `onchain_last_error` for admin review.

### Risk 4 — Profile-creation race
**What:** Two concurrent workouts for a new user both hit `ensureUserProfile`, both mint a new `UserProfile`. We end up with duplicate profiles and the second workout's `submit_workout` fails against a profile the operator may not own.

**Fix (not shipped yet):** Serialize profile creation per athlete via a D1 lock row or Durable Object. Low priority — happens only on first-ever submission AND only if the user taps Save twice within a few hundred ms.

### Risk 5 — Version-object contention
**What:** `SUI_VERSION_OBJECT_ID` is a shared object referenced by every `submit_workout`. Under high concurrency this is a classic Sui hot-object bottleneck.

**Fix:** The Move module already follows the versioned-shared-object pattern; actual contention only hurts when many writes happen in the same checkpoint. Fanout (Risk 1 fix) is the mitigation — each operator gets its own mempool slot.

## What this audit recommends shipping next

In priority order, assuming the goal stays "testnet-complete first, then mainnet":

1. **Reconciler** ✅ shipped in this commit
2. **Multi-operator fanout** — next lift; unblocks mainnet scale
3. **Profile-creation serialization** — defensive; cheap once we add a generic Durable-Object lock helper
4. **Hardware-backed oracle key** — mainnet blocker; can be deferred until shortly before launch
5. **Sponsored-tx path** — nice-to-have; only needed if we let users sign with their own wallets for some premium flows

Everything above is decoupled from the Move contract. The on-chain surface area doesn't change for any of it.

## Monitoring

Admin dashboard (`/admin/dashboard`) should grow a tile showing:
- `pending_` workouts count
- Distribution by `onchain_retry_count`
- Last `onchain_last_error` across the top-N rows

Added to the admin-dashboard task list.
