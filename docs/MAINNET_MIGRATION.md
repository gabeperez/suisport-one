# Mainnet migration

This is the punch list for moving SuiSport ONE from Sui testnet to mainnet. Treat it as a runbook, not a doc — every step has an explicit action.

The audit pass that produced the punch list lives below in `docs/MAINNET_AUDIT.md` (refreshed on each audit run). This doc is the migration recipe; the audit doc is the *what could go wrong*.

---

## Phase 0 — pre-migration sanity (do this 1 week before)

- [ ] Confirm no testnet-only code paths remain (see Audit Tier 🔴)
- [ ] Lock the canonical SuiSport ONE branding — bundle id, app icon, App Store screenshots
- [ ] Commission a security review of the Move package (oracle digest construction, replay protection, version-object upgrade behavior)
- [ ] Decide on the **operator key custody** — KMS / Turnkey / hardware HSM. Cloudflare wrangler-secrets-only is acceptable for testnet but not for a production reward minter
- [ ] Sign a contract with at least 2 commercial Walrus publisher endpoints + 1 commercial Sui RPC provider (Mysten + a backup)
- [ ] Confirm Apple App Attest production environment is configured for the bundle id
- [ ] Confirm Apple Push Notifications is set up with a production APNs key (separate from sandbox)
- [ ] Run a load test on the testnet pipeline at 10× expected mainnet day-1 volume

## Phase 1 — Move package publish

```bash
# 1. Switch sui CLI to mainnet
sui client switch --env mainnet

# 2. Verify the publishing keypair has enough SUI for gas
sui client gas

# 3. Bump the package version in Move.toml if you haven't already.
#    Mainnet should not start at v1 — start at v2 so testnet artifacts
#    can never accidentally interact.
vim move/suisport/Move.toml

# 4. Build + publish
cd move/suisport
sui move build
sui client publish --gas-budget 200_000_000

# 5. Capture from the publish output:
#    - SUI_PACKAGE_ID            (the new "Created" Package object id)
#    - SUI_REWARDS_ENGINE_ID     (the new shared RewardsEngine)
#    - SUI_ORACLE_CAP_ID         (the new owned OracleCap — transfer to operator addr)
#    - SUI_VERSION_OBJECT_ID     (the new shared Version)
```

## Phase 2 — keypairs + funding

```bash
# 1. Generate fresh mainnet operator keypair(s) — multi-operator pool ready
sui client new-address ed25519
# repeat for as many operators as you want in SUI_OPERATOR_KEYS
# fund each with at least 5 SUI for ~10k initial workout submissions

# 2. Generate fresh oracle keypair
#    DO NOT reuse the testnet oracle key — its base64 may be in shell
#    history, log files, or wrangler-secret-history.
python3 cloudflare/scripts/gen_oracle_key.py
# capture the base64 secret + the hex public key

# 3. Tell the Move contract about the new oracle public key
sui client call \
  --package <PACKAGE_ID> --module rewards_engine \
  --function set_oracle_pubkey \
  --args <ORACLE_CAP_ID> <ORACLE_PUBKEY_HEX> <VERSION_OBJECT_ID> \
  --gas-budget 10_000_000

# 4. Move the OracleCap into the operator's address
sui client transfer --object-id <ORACLE_CAP_ID> --to <OPERATOR_ADDR>
```

## Phase 3 — Cloudflare Worker secrets

Set every one of these for the production Worker. **Do not commit any of these to git.**

```bash
cd cloudflare

# Sui mainnet
wrangler secret put SUI_NETWORK            # "mainnet"
wrangler secret put SUI_PACKAGE_ID
wrangler secret put SUI_REWARDS_ENGINE_ID
wrangler secret put SUI_ORACLE_CAP_ID
wrangler secret put SUI_VERSION_OBJECT_ID
wrangler secret put SUI_OPERATOR_KEYS      # comma-separated for multi-op
wrangler secret put ORACLE_PRIVATE_KEY     # base64 ed25519 secret seed

# Walrus mainnet
wrangler secret put WALRUS_PUBLISHER_URL
wrangler secret put WALRUS_AGGREGATOR_URL

# Enoki mainnet (separate API key from testnet)
wrangler secret put ENOKI_SECRET_KEY

# App Attest production
wrangler secret put APPATTEST_APP_ID       # "<TEAM_ID>.<BUNDLE_ID>"
wrangler secret put APPATTEST_ENV          # "production"

# APNs production (separate p8 from sandbox if you used one)
wrangler secret put APNS_KEY               # AuthKey_<id>.p8 contents
wrangler secret put APNS_KEY_ID
wrangler secret put APNS_TEAM_ID
wrangler secret put APNS_BUNDLE_ID
wrangler secret put APNS_ENV               # "production"

# Admin
wrangler secret put ADMIN_TOKEN            # generate fresh, ≥ 64 chars

# Optional — see audit doc for whether these apply on mainnet
wrangler secret put ATTEST_STRICT          # "true" — refuse non-attested submissions
```

After all secrets are set:

```bash
wrangler deploy
```

## Phase 4 — D1 / R2 fork

The hackathon backend is shared with the canonical SuiSport. **Do not** point mainnet at the same D1 — testnet demo rows would pollute the prod ledger.

```bash
# 1. Create a new D1 + R2 for prod
wrangler d1 create suisport-one-prod
wrangler r2 bucket create suisport-one-media-prod

# 2. Update wrangler.toml's [[d1_databases]] + [[r2_buckets]] to point
#    at the new ids
vim cloudflare/wrangler.toml

# 3. Apply every migration from scratch on the new DB
wrangler d1 migrations apply suisport-one-prod --remote

# 4. Seed initial trophy + rewards-catalog rows ONLY (no demo athletes)
wrangler d1 execute suisport-one-prod --remote --file=./prod-seed.sql

# 5. Re-deploy the worker
wrangler deploy
```

## Phase 5 — iOS client switch

```swift
// iHealth/Services/APIClient.swift
let baseURL = URL(string: "https://api.suisport.app/v1")!  // or workers.dev mainnet

// iHealth/Services/WalletConnectBridge.swift
// bridgeURL → mainnet wallet-bridge Pages project
```

```bash
# Update the bundle id if you want isolation from testnet builds
# (App Attest bindings are bundle-id-keyed; no migration concern)

# Submit to TestFlight, then App Store review
# App Attest: must be on production env in pbxproj's
# `INFOPLIST_KEY_NS...UsageDescription` strings
```

## Phase 6 — Walrus blob migration

Existing testnet Walrus blobs **stay on testnet Walrus**. They cannot be moved. The mainnet pipeline starts a new blob set.

If you want to keep historical workout proofs:
- Export each `Workout` row's canonical JSON from D1
- Re-upload to mainnet Walrus
- Update `walrus_blob_id` column for migrated rows

This is optional — most users don't care about pre-mainnet workouts.

## Phase 7 — Switchover day

- [ ] Pause testnet operator keys (set `MAINTENANCE_MODE=true` env var; refuse new submissions)
- [ ] Drain the on-chain retry queue on testnet
- [ ] Run final `wrangler deploy --env production`
- [ ] DNS cut: `api.suisport.app` → mainnet Worker
- [ ] App Store: ship the build with mainnet `APIClient.baseURL`
- [ ] Monitor for 48h: D1 errors, APNs failure rate, Sui tx success rate, Walrus 503s
- [ ] If anything's red, see Phase 8 rollback

## Phase 8 — Rollback

If mainnet falls over in the first 48h:

1. Flip `APIClient.baseURL` back to testnet via remote config (we should add a remote config endpoint before launch — see audit doc)
2. Or push a hotfix iOS build via TestFlight expedited
3. Mainnet Move package can't be unpublished, but you can pause via the `Version` object's `paused: bool` flag (check the contract; if it doesn't have one, we should add it before mainnet)
4. Reset `SUI_NETWORK=testnet` on the worker; users sign back into testnet — embarrassing but not fatal

---

## Money flow audit (the part that actually matters on mainnet)

| Variable | Testnet value | Mainnet value | Why |
|---|---|---|---|
| SWEAT mint per workout | uncapped (per-minute base × multipliers) | **needs a daily cap** | Otherwise someone runs 24h on a treadmill and mints 86,400 minutes worth of SWEAT |
| Trophy mints | unlimited per athlete | **idempotent per camp completion** (already uses `INSERT OR IGNORE` in `trophy_unlocks` — verify this protects under network races) | Otherwise dupes |
| Stake amounts on Challenges | demo values (50–100 SWEAT) | review per-challenge stakes | Could be too high or too low for real demand |
| Reward redemption | off-chain code-pop | confirm code pool isn't shipped in `rewards_catalog` for prod | Otherwise reviewing the public schema reveals codes |

## Compliance + privacy checklist

- [ ] GDPR: confirm `/me/export` returns every row associated with the user
- [ ] GDPR: confirm `/me/delete` purges every row including push tokens, attestation keys, redemption history
- [ ] App Store: HealthKit declaration in `INFOPLIST_KEY_NSHealth*UsageDescription` accurate for production
- [ ] App Store: privacy nutrition labels updated for the new permissions (Health + push + location)
- [ ] Walrus: confirm storage TTL is set high enough that historical workouts don't expire silently
- [ ] D1 backup schedule (Cloudflare runs nightly snapshots; verify retention is at least 30 days)

## Operator + Oracle key custody (must do)

Cloudflare wrangler secrets are *fine* for testnet. They're **not fine** for mainnet because:

- Anyone who compromises the Cloudflare account holds both the SWEAT mint authority AND the gas wallet
- Operator key compromise = unlimited SWEAT mint
- Oracle key compromise = forgeable workout attestations

**Recommended for mainnet day 1:**

- Move oracle signing into a Cloudflare Worker that talks to AWS KMS / GCP KMS / Turnkey for the actual signing operation. Worker never sees the seed.
- Operator keys can stay in wrangler secrets short-term but should rotate to KMS within 30 days. The multi-operator fanout already enables key rotation without contract changes.

The architecture for KMS-backed oracle signing is laid out in `docs/ON_CHAIN_STRATEGY.md`. Implementation is ~150 LOC in `cloudflare/src/sui.ts` and a one-off IAM setup in AWS.

## Sign-off checklist before flipping the DNS

- [ ] All BLOCKER + HIGH items in `docs/MAINNET_AUDIT.md` resolved
- [ ] Move package published, all object ids captured + verified via `sui client object`
- [ ] Operator keys funded with at least 50 SUI total
- [ ] Oracle key set on the contract via `set_oracle_pubkey`
- [ ] Worker deployed with all mainnet secrets
- [ ] D1 migrations applied to prod DB
- [ ] iOS build with prod `APIClient.baseURL` submitted to TestFlight
- [ ] At least 1 internal team member completes a full workout-submit + reward-mint cycle on mainnet via TestFlight
- [ ] Monitoring: Sentry / Cloudflare Analytics / D1 query dashboards configured + on-call rotation set
- [ ] Press release / changelog ready

When the box above is fully checked, flip `SUI_NETWORK=mainnet` on the production Worker and push the iOS build to App Store review.

---

*This doc is a living recipe. When you find a step missing or a gotcha not captured here, edit it. The next person migrating an Sui dApp will thank you.*
