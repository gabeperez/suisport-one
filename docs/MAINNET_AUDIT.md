# Mainnet readiness audit

Run on 2026-04-25 against commit `2a112fb` of the SuiSport ONE codebase.

This is the *what could go wrong* doc. The migration recipe is at [`MAINNET_MIGRATION.md`](./MAINNET_MIGRATION.md).

Severity legend:

- 🔴 **BLOCKER** — will break or be exploitable on mainnet. Fix before flipping `SUI_NETWORK=mainnet`.
- 🟠 **HIGH** — should be done before launch.
- 🟡 **MEDIUM** — do within first month.
- 🟢 **NICE** — nice to have.

---

## 1. Move package (`move/suisport/`)

| | What | Where |
|---|---|---|
| 🔴 | `Move.toml` is `suisport = "0x0"`. Mainnet publish needs a separate `[env.mainnet]` block + a fresh package address. Don't reuse the testnet `0x9666…452b`. | `Move.toml:10` |
| 🔴 | `Version` is initialized at `value: 1` and `bump()` is `public(package)` but no AdminCap-gated entry exposes the bump. Upgrade pattern is non-functional today. Add `admin::bump_version(_admin: &AdminCap, v: &mut Version)` before launch. | `version.move:15` |
| 🔴 | `init` mints the AdminCap to the publisher; runbook MUST move it into a 2-of-3 multisig before minting OracleCap, or a single hot key controls both pause + oracle rotation. | `admin.move:33–36` |
| 🟠 | `initialize` takes `epoch_cap` + `per_user_cap` with no documented sane defaults. Pin specific values (e.g. `epoch_cap = 1_000_000 × 1e9`, `per_user_cap = 1_000 × 1e9`) in the publish script. | `rewards_engine.move:66–88` |
| 🟠 | `coin::mint` per submission has no per-tx ceiling. Bounded only by `per_user_cap` per epoch. Add `assert!(reward_amount <= MAX_REWARD_PER_WORKOUT, …)`. | `rewards_engine.move:189` |
| 🟠 | `challenges::resolve` takes `_oracle: &OracleCap` but never checks `oracle_revoked()`. Compromised oracle would still pay out. Add the assertion. | `challenges.move:82–104` |
| 🟡 | `balance::join(&mut c.stake_a, b); balance::join(&mut c.stake_a, a);` — write a Move test that the payout total equals `amount_a + amount_b`. | `challenges.move:97–99` |
| 🟡 | `attach_workout` is dead code — `rewards_engine` never calls it; `workout_registry::mint_workout` does the soulbound transfer. Remove or wire up. | `user_profile.move:70–77` |
| 🟡 | SWEAT coin metadata icon URL is hardcoded `https://suisport.app/sweat-icon.png`. Metadata is frozen — verify domain ownership and serve a real PNG before publish. | `sweat.move:27–29` |

## 2. Backend env / Cloudflare Worker

| | What | Where |
|---|---|---|
| 🔴 | `(env.SUI_NETWORK || "testnet")` defaults silently to testnet. On a misconfigured mainnet deploy the worker routes to testnet RPC. Make it throw, or default to mainnet when `ENVIRONMENT === "production"`. | `sui.ts:155` |
| 🔴 | `DEFAULT_PUBLISHER` / `DEFAULT_AGGREGATOR` hardcoded to `walrus-testnet.walrus.space`. Replace with mainnet endpoints, or throw when unset. | `walrus.ts:12–13` |
| 🔴 | Same default-testnet pattern for `network` resolution. | `routes/sui.ts:13`, `routes/sui.ts:45–46` |
| 🔴 | Dev fallback accepts any `?athleteId=0xdemo_*` or any `0x[64hex]` as an authenticated identity. **Anyone can submit workouts as anyone else** without a session token. Comment-flagged "Remove in prod" — strip on mainnet. | `auth.ts:23–28` |
| 🔴 | Demo identity fallback `c.get("athleteId") ?? "0xdemo_me"` makes unauthenticated `/me` resolve to a demo athlete. | `routes/social.ts:41`, `routes/social.ts:422` |
| 🔴 | When `ENOKI_SECRET_KEY` is unset, `deterministicAddr()` derives a fake 40-hex address from the id token. On mainnet this MUST hard-fail. | `routes/auth.ts:58–60`, `routes/auth.ts:290–297` |
| 🟠 | No `[env.production]` split in `wrangler.toml` — only one D1 + R2 binding, deployed on workers.dev. Stand up a `production` env with a custom domain + separate D1 + R2. | `wrangler.toml` |
| 🟠 | `ATTEST_STRICT?` defaults to OFF — mutating routes accept requests with no attestation header. Mainnet MUST set `"true"` or App Attest is decorative. | `env.ts:21` |
| 🟠 | `ADMIN_TOKEN` declared as required string; no length validation. Verify ≥ 32 random bytes and rotate before launch. | `env.ts:5` |
| 🟠 | `cors({ origin: "*" })` is open. Lock to known origins (Pages bridge + iOS-uses-no-Origin); not strictly needed for the iOS app but reduces admin-token exposure window. | `index.ts:20–25` |
| 🟡 | Rate limit at 60/min/key. Mainnet should be ≤ 30/min and add a per-IP bucket — Sybil with 100 sessions = 6000/min from one IP today. | `wrangler.toml:25` |

## 3. iOS hardcoded URLs / constants

| | What | Where |
|---|---|---|
| 🔴 | `baseURL = "https://suisport-api.perez-jg22.workers.dev/v1"` — personal workers.dev subdomain shipped in App Store binary. Move to `api.suisport.app` (or whatever) with build-time staging variants. | `APIClient.swift:16` |
| 🔴 | `var demoAthleteId: String? = "0xdemo_me"` ships as a default. Combined with the server-side fallback above, every request without a session token authenticates as the demo user. Set default to `nil`. | `APIClient.swift:22` |
| 🔴 | `https://suisport-wallet.pages.dev/` — same workers.dev personal subdomain as a hardcoded URL. | `WalletConnectBridge.swift:170` |
| 🔴 | `OnChainBadge.explorerBase = "https://suiscan.xyz/testnet/tx"` — every "On-chain" badge in the app deep-links to the testnet explorer. Make it network-aware (read `/v1/sui/status` on first launch + cache). | `DesignSystem/Components.swift:265` |
| 🟠 | `defaultNetwork="testnet"` in the wallet bridge SPA — Slush will display "Testnet" pill even on mainnet. Switch to `"mainnet"` when the app deploys. | `cloudflare/wallet-bridge/src/main.jsx:46` |
| 🟡 | Google `clientId` for project `424529031571`. Verify the OAuth client is configured for the production bundle id and listed as an authorized domain in Enoki's mainnet project. | `Services/GoogleAuth.swift:23–24` |

## 4. App Attest

| | What | Where |
|---|---|---|
| 🟠 | `APPATTEST_ENV?` defaults to `"production"` only when *explicitly absent*. If a stale `dev.vars` file leaks `"development"` into prod, AAGUID expectations silently flip. Verify the prod secret is `"production"` exactly. | `env.ts:17` |
| 🟢 | Apple App Attest Root CA is the production root, valid through 2045. No action. | `appattest.ts:52–65` |

## 5. Operator + Oracle keys

| | What | Where |
|---|---|---|
| 🔴 | Operator + oracle keys are base64 plaintext in Cloudflare Secrets. No HSM/KMS. Worker compromise = unbounded mint within rate caps + gas drain. Migrate oracle to remote-signing (AWS KMS attestation lambda). Move AdminCap into a Sui multisig held off-platform. | `sui.ts:30–46`, `sui.ts:196–201` |
| 🟠 | `admin::rotate_oracle` exists on-chain but no off-chain runbook. Add a script: generate new key → multisig calls `rotate_oracle` → push new secret → roll workers. | `admin.move:43–48` |

## 6. Money flow

| | What | Where |
|---|---|---|
| 🟠 | Reward formulas have no daily cap. A 50 km bike ride mints ≥ 3000 SWEAT (× 1e9 = 3 × 10¹² base units). 24-hour treadmill = 86 400 minutes worth. Tokenomics need to be set BEFORE mainnet — both the per-workout multipliers AND the per_user_cap on chain. | `iHealth/Models/SweatPoints.swift:24–59` |
| 🟠 | `maxPointsByMinute = 4` server cap — a 24-hour workout claims 5760 points = 5760 SWEAT. Lower this and add a per-day total cap. | `cloudflare/src/fraud.ts:98–103` |
| 🟡 | `challenges::resolve` transfers full pot to winner with no protocol rake / burn even though the file's comments say there should be one. Decide intent. | `challenges.move:82–104` |
| 🟡 | Trophy mints are off-chain in `trophy_unlocks`. Free for the user, no SWEAT cost. Confirming this is intentional. | `routes/workouts.ts:392–401` |

## 7. Rate limits / abuse

| | What | Where |
|---|---|---|
| 🟠 | `RATE_LIMIT.limit({ key })` keys on athleteId-or-IP. Sybil farms separate athleteIds via free Google accounts and gets full quota each. Add a second IP-keyed bucket. | `auth.ts:108–122` |
| 🟠 | Canonical workout-hash buckets distance to 10m and HR to 5 bpm. A trivial 60s start-time jitter sidesteps the dedup. Apple Watch path goes uncapped (manual capped at 30%). Tighten. | `fraud.ts:31–61` |
| 🟢 | A single user with N attested devices = N × rate-limit. Document. | — |

## 8. Privacy / GDPR

| | What | Where |
|---|---|---|
| 🟢 | `/me/export` returns the `sessions.id` column — that's the bearer token. Drop or redact `s.id` from the export so a leaked export isn't a session leak. | `routes/account.ts:10–55` |
| 🟢 | `DELETE /me` correctly notes Walrus blob persistence; make sure the privacy policy explicitly covers it. | `routes/account.ts:60–95` |

## 9. Admin surface

| | What | Where |
|---|---|---|
| 🟠 | `adminGuard` does plain `token !== c.env.ADMIN_TOKEN`. No timing-safe compare. Use a constant-time check. | `auth.ts:40–50` |
| 🟠 | No `admin_audit` table tracking *who* did *what*. `admin.ts:118–152` (resolve report, suspend) write to D1 but the actor is "admin" or self-supplied. Add a real audit log. | `routes/admin.ts:118–152` |
| 🟠 | `/v1/admin/dashboard` returns HTML; auth is enforced via the `admin.use("*", adminGuard)` wrapper, but the dashboard's own JS prompts for the token client-side. Confirm the wrapper actually covers the dashboard route by curl-ing it without a header on staging. | `routes/admin.ts:241–243` |

## 10. D1 / indexer

| | What | Where |
|---|---|---|
| 🔴 | Indexer cursor lives in `schema_meta.sui_indexer_cursor` and references testnet `txDigest` values. On the first mainnet tick, this row will fail or skip. Wipe `sui_indexer_cursor` row + `sui_events` table on mainnet first deploy. Also wipe `sui_user_profiles` (testnet object IDs are useless on mainnet). | `indexer.ts:42–47` |
| 🔴 | `cloudflare/seed.sql` populates 12 demo athletes + sessions. On mainnet, run `POST /v1/admin/clear-demo` (or skip seeding entirely). The `0xdemo_*` athlete ids fail the "real Sui address" assumption. | `cloudflare/seed.sql` |
| 🟡 | `/health` exposes `demoSeeded`. Harmless, but on mainnet should always be 0. | `index.ts:40–49` |

## 11. Push notifications

| | What | Where |
|---|---|---|
| 🟢 | DEBUG → APNS env=sandbox; release → production. TestFlight is release config so production is correct. Verify `APNS_ENV` worker secret matches what TestFlight builds report by sending one test push. | `PushNotifications.swift:81–85` |

## 12. Misc

| | What | Where |
|---|---|---|
| 🟠 | `BigInt(body.points) * 1_000_000_000n` — `body.points` comes from the client. Server vets via `vetWorkout` but the client-supplied number still propagates straight to the mint amount. Recompute server-side from the validated workout payload. | `routes/workouts.ts:130` |
| 🟠 | `txDigest = pending_${workoutId}` sentinel. Confirm the indexer / retry path filters via `LIKE 'pending_%'` (it does, but worth re-reading). | `routes/workouts.ts:117` |
| 🟡 | `suiObjectId: null` always returned in the initial workout-submit response. Indexer back-fills later. Document in the iOS client so the UI can show a "settling" state. | `routes/workouts.ts:166`, `indexer.ts:121–130` |
| 🟢 | Stand up the staging `[env.staging]` block in `wrangler.toml` before mainnet so upgrades can be dry-run. | `wrangler.toml:38–49` |

---

## Top 10 to fix in priority order

1. **Demo identity fallbacks** in `auth.ts` + `social.ts` + `auth.ts` route — gate behind `ENVIRONMENT !== "production"` so the worker hard-fails on mainnet.
2. **Network defaults** in `sui.ts`, `walrus.ts`, `routes/sui.ts` — throw or default to mainnet when `ENVIRONMENT === "production"`.
3. **Constant-time admin token compare** in `auth.ts:40–50`.
4. **iOS `demoAthleteId` default** — set to `nil`; add a build flag for testnet builds to override.
5. **Daily SWEAT mint cap** — both the per-workout multiplier in `SweatPoints.forWorkout` AND a server-side per-day total in `fraud.ts`.
6. **Per-tx mint ceiling in Move** — `assert!(reward_amount <= MAX_REWARD_PER_WORKOUT, …)` in `rewards_engine`.
7. **Server-side recompute of points** — drop `body.points`, recompute from canonical workout payload.
8. **AdminCap multisig** — generate fresh AdminCap on mainnet, transfer immediately to a 2-of-3 Sui multisig, then mint OracleCap.
9. **Apple App Attest production env** confirmed in `APPATTEST_ENV` worker secret.
10. **Wipe demo seed + indexer cursor** on the first mainnet D1 (handled in `MAINNET_MIGRATION.md` Phase 4).

When all 10 are done, walk back through the rest of this doc with a checkbox per item before flipping the DNS.
