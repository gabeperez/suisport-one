# SuiSport — what's left

What we've already shipped is in `FRIENDS_BETA.md`. Everything below is
what still needs doing, grouped by who has to do it.

**Last updated:** 2026-04-24 (post-§2-bulk-pass)

---

## 1. Needs your input (I can't do these from here)

These block actual testing and shipping. In rough priority order:

### 1.1 — Open the project in Xcode and hit Cmd+R
Every edited Swift file parses clean via `swift -frontend -parse`, but
xcodebuild was killed silently in this sandbox so I couldn't verify a
full iOS build. Open the project, build for your iPhone 17 Pro
simulator, and confirm:
- Feed loads with the DEMO chip showing
- Pull-to-refresh on Feed + Clubs hits the live Worker
- Profile → Edit → Add shoe round-trips to the server
- Sign-in flow doesn't crash (still mock auth)

Any compile errors → paste back, I'll fix. This is the gate before
anything else.

### 1.2 — Cloudflare API token for CI
GitHub Actions needs these repo secrets to auto-deploy:
- `CLOUDFLARE_API_TOKEN` — create at `https://dash.cloudflare.com/profile/api-tokens`
  with scopes: **Workers Scripts: Edit**, **D1: Edit**, **R2: Edit**
  (limit to your account)
- `CLOUDFLARE_ACCOUNT_ID` = `1be5e8b0e95f6466ce392e3be13d816b`

Add via GitHub repo → Settings → Secrets and variables → Actions →
New repository secret. Then push to `main` and watch `.github/
workflows/worker-ci.yml` run.

### 1.3 — Push the repo somewhere
Four focused commits sit on top of `main` locally. Create a GitHub
repo and `git push -u origin main` so CI has something to run against.
I left history alone (didn't rewrite the old "Graphical version"
commit that accidentally shipped node_modules) — that's your call on
whether to rebase it away later.

### 1.4 — TestFlight provisioning
Required to share the iOS app with friends over-the-air. Needs:
- Apple Developer Program membership ($99/yr)
- App ID registered with `Associated Domains` + `HealthKit` +
  `App Attest` capabilities
- Provisioning profile in Xcode Signing & Capabilities
- Archive → Distribute App → App Store Connect → Upload
- Invite testers via App Store Connect TestFlight tab (up to 10k
  external testers for 90 days)

Steps in `FRIENDS_BETA.md`.

### 1.5 — Enoki API key (when you're ready to flip real auth on)
Sign up at `https://enoki.mystenlabs.com`, create an app, register
OAuth providers (Google client id, Apple service id), copy the
**secret** API key (`enoki_secret_...`), then:
```sh
cd cloudflare
echo "enoki_secret_..." | wrangler secret put ENOKI_SECRET_KEY
wrangler deploy
```
From that moment, `/v1/auth/session` performs real zkLogin — the
deterministic mock is gone. iOS side still needs the Google OAuth
flow wired (see 2.4 below).

### 1.6 — App Attest app id
```sh
cd cloudflare
echo "<TEAMID>.gimme.coffee.iHealth" | wrangler secret put APPATTEST_APP_ID
wrangler deploy
```
The TEAMID is your Apple Developer team id (10 chars, Apple Developer
portal → Membership). Without this secret, attestation register still
works but skips the rpIdHash check.

### 1.7 — Lawyer review of `legal/PRIVACY.md` and `legal/TERMS.md`
The templates cover HealthKit, on-chain data retention, $SWEAT
classification, GDPR rights, limitation of liability, and an age gate.
They are **not legal advice** — a real lawyer needs to fill in every
`[BRACKETED]` placeholder and confirm the crypto-rewards language
doesn't expose you to SEC/FTC action. Flag this to your lawyer
specifically:
> "Sweat Points → $SWEAT token swap. Is this a registered security, a
> reward program, or neither under US / EU law? We currently document
> it as a non-security utility reward."

### 1.8 — Custom domain
`workers.dev` URLs work but look amateur. When you're ready:
1. Add `suisport.app` (or whatever) in Cloudflare DNS
2. In `wrangler.toml`, replace `workers_dev = true` with:
   ```toml
   [[routes]]
   pattern = "api.suisport.app/*"
   zone_name = "suisport.app"
   ```
3. Deploy — DNS propagates within minutes.
4. Update `APIClient.baseURL` in `iHealth/Services/APIClient.swift`.

---

## 2. Future engineering (I can do these — just haven't yet)

### 2.1 — Real cert-chain verification in App Attest
Right now we CBOR-decode the attestation, verify authData structure,
check nonce via challenge consumption, and extract the EC P-256 public
key — then store with `cert_chain_ok = 0`. Missing: full x5c chain
validation against Apple's App Attest Root CA. This is ~300 lines of
ASN.1/X.509 parsing; `@peculiar/x509` is a candidate. Until this lands,
a determined attacker could forge an attestation object if they
extracted the leaf cert — acceptable for beta, not for mainnet rewards.

### 2.2 — ~~Assertion verification middleware~~ ✅ SHIPPED
`attestMiddleware` registered after rate-limit on every non-GET
route. Default non-strict: requests without headers pass through so
existing clients aren't broken. Flip `ATTEST_STRICT=true` as a
wrangler secret to require valid headers on every mutating call.
iOS still needs to **send** the headers (generate assertion via
`DCAppAttestService.generateAssertion`); infrastructure is there.

### 2.3 — Walrus upload pipeline
`POST /v1/workouts` returns `txDigest: pending_<id>`. To actually anchor
the workout on-chain:
- Canonicalize the workout payload to bytes
- Upload via Walrus SDK → get blobId
- Build Sui PTB: `workout_registry::submit(walrus_blob_id, hash, points)`
- Sign via Enoki sponsored tx (requires Enoki configured)
- Store `walrus_blob_id`, `sui_object_id`, `sui_tx_digest` on the workout
- Hand off to a Cloudflare Queue so the HTTP request doesn't block on
  chain finality (needs Workers Paid $5/mo)

### 2.4 — Real iOS auth flow
Currently `AuthService.signInWithApple()` + `signInWithGoogle()` return a
deterministic fake. Replace with:
- **Apple:** use `ASAuthorizationAppleIDRequest` (already imported in
  `AuthService.swift`), capture the identity token, POST to
  `/v1/auth/session` with `{ provider: "apple", idToken }`.
- **Google:** add `GoogleSignIn` SPM package, call
  `GIDSignIn.sharedInstance.signIn(withPresenting:)`, capture
  `user.idToken.tokenString`, POST the same way.

Once Enoki is configured (1.5), the Worker resolves the id token to a
real Sui address. Store the returned `sessionJwt` in Keychain.

### 2.5 — Sentry / Crashlytics for iOS + Logpush for Worker
Not today's blocker but you'll want them before opening the beta wider:
- **iOS:** Add Sentry-Cocoa via SPM, set DSN from Apple Developer
  dashboard env, capture crashes + breadcrumbs.
- **Worker:** Enable Logpush → R2 in CF dashboard (Workers →
  suisport-api → Settings → Logs). Rotate logs at 30 days.

### 2.6 — Move contracts to testnet
`move/suisport/sources/` has 7 contract modules (`sweat`, `admin`,
`version`, `rewards_engine`, `workout_registry`, `user_profile`,
`challenges`). None are deployed. Before `$SWEAT` becomes real:
- `sui move build` — confirm clean compile
- Deploy to testnet: `sui client publish --gas-budget 100000000`
- Audit. The `rewards_engine.move` + `sweat.move` especially need a
  serious review before any real mint happens. Recommend an
  independent auditor (OtterSec, Halborn, Movebit).
- Bring iOS + Worker up to speed on the package id.

### 2.7 — Durable Objects for live chat + real-time kudos
Currently club chat is absent. Adding:
- One Durable Object class per club for chat
- WebSocket upgrade from the Worker
- Store last 100 messages in DO storage; overflow to D1
- Needs Workers Paid ($5/mo)

### 2.8 — D1 read replicas
Enable in CF dashboard when latency-sensitive reads get busy
(probably not until you have a few hundred MAU). Free on Workers Paid.

### 2.9 — ~~Richer on-chain indexer~~ ✅ SHIPPED
Indexer walks rewards_engine + workout_registry in parallel each
tick, upserts sweat_points (so brand-new athletes get a row
created on first mint), writes a health heartbeat to
schema_meta.sui_indexer_health with timestamp + last-event-ts +
error fields, and exposes the block via `/v1/sui/status.indexer`.
*Future*: swap for Shinami or Mysten's hosted indexer when it
supports the custom Move structs; our own works for the beta.

### 2.10 — ~~Moderation review queue~~ ✅ SHIPPED
Migration 0007 added `reports.resolved_at / resolution_note /
resolved_by`. Admin endpoints: `GET /v1/admin/reports`,
`POST /v1/admin/reports/:id/resolve`, suspend/unsuspend athletes.
`GET /v1/admin/dashboard` is a self-contained HTML page behind
`X-Admin-Token`. Feed + `/athletes` filter out suspended athletes.
*Future polish*: Slack webhook on new reports, auto-escalation by
reason count, shadow-ban (reports still accept, nobody sees).

### 2.11 — iOS UI refinements (partial ✅)
Shipped:
- ~~Launch screen~~ — LaunchBackground color asset + Info.plist
  wiring so the launch state reads as SuiSport (deep green / near-
  black dark) instead of a white flash.
- ~~iPad max-width readability~~ — Feed + Profile content clamped
  to 640pt on wide devices.
Still open:
- App Icon (still Xcode template — needs a real 1024×1024 PNG)
- App Store screenshots + metadata
- Dark-mode audit pass on every onboarding screen (core surfaces OK)

### 2.12 — ~~Live workout recorder~~ ✅ SHIPPED
LiveRecorderView drives `WorkoutRecorder`. Full-screen cover from
RecordSheet; HK session lifecycle (prepare → running → paused →
saving → finished); giant duration counter + 4 metric tiles
(distance, pace, HR, kcal); pause/resume/end confirm → submit to
`/v1/workouts` → refresh feed. **Needs real iPhone + Simulator to
validate runtime behavior** — HealthKit APIs only exercise at
build time.

---

## 3. Known gaps + risks

- **API is on `workers.dev`.** Anyone who finds the URL can hit it.
  Rate-limiting (60 req/min) + auth-gated mutations mitigate but don't
  fully prevent scraping of public GET endpoints. Custom domain + CF
  WAF rules when you're serious.
- ~~**Canonical-hash dedup uses minute-granularity.**~~ ✅ FIXED —
  hash now buckets energy_kcal (25 kcal) + avg_heart_rate (5 bpm) in
  addition to start-minute + duration + distance. Two distinct workouts
  won't false-collide in practice.
- **Mock Enoki returns predictable addresses.** Anyone can generate the
  same fake Sui address by SHA-256 hashing a known id_token. Not a
  real problem until mock auth is on a URL that anyone can hit — if you
  invite friends, the mock address is fine; if you open the URL wider,
  switch to 1.5 first.
- ~~**No ban/unban.**~~ ✅ FIXED — `POST /v1/admin/athletes/:id/suspend|unsuspend`
  plus the admin dashboard flip it. Feed filters out suspended content.
- ~~**No age verification**~~ ✅ FIXED — age-gate onboarding step
  captures DOB, blocks under 13, PATCHes server with `dob` for
  compliance record.

---

## 4. Cost trajectory

- **Now, free tier:** $0/mo.
- **Workers Paid ($5/mo flat):** unlocks Durable Objects, Queues, longer
  Worker CPU, Logpush, 50x D1 capacity. Required for chat (2.7), async
  attestation pipeline (2.3), and log archival (2.5).
- **Apple Developer:** $99/yr.
- **Legal review:** $1k-5k one-time depending on jurisdiction + firm.
- **Security audit of Move contracts (before mainnet):** $10k-50k.
- **Domain:** ~$12/yr on CF Registrar.

---

## 5. Changelog reference

| Scope | Shipped in | File |
|---|---|---|
| Local app + onboarding + design system | iOS initial | `iHealth/` |
| Move scaffold | Move initial | `move/` |
| Fastify backend (legacy, superseded) | initial | `backend/` |
| CF Worker + D1 + R2 + seed | scope #1 | `cloudflare/` |
| DemoChip + local-seed tagging | scope #1 | `iHealth/DesignSystem/Components.swift` |
| Worker auth/validation/rate-limit + migrations + staging + CI + gitignore + runbook + iOS API wiring + APIClient retry | scope #1 | `cloudflare/`, `iHealth/Services/`, `.github/`, `FRIENDS_BETA.md` |
| Enoki zkLogin scaffold (gated on secret) | scope #2 | `cloudflare/src/enoki.ts` |
| App Attest endpoint + CBOR + key store | scope #2 | `cloudflare/src/appattest.ts` |
| GDPR delete + export | scope #2 | `cloudflare/src/routes/account.ts` |
| Anti-fraud baseline (hash dedup + velocity + pace + points cap) | scope #2 | `cloudflare/src/fraud.ts` |
| Privacy + Terms templates | scope #2 | `legal/` |
| This TODO | scope #2 | `TODO.md` |
| Moderation queue + soft-ban + age gate + canonical-hash hardening | scope #3 | `cloudflare/migrations/0007_*`, `cloudflare/src/routes/admin.ts`, `iHealth/Features/Onboarding/AgeGateScreen.swift`, `cloudflare/src/fraud.ts` |
| Feed cursor pagination | scope #3 | `cloudflare/src/routes/social.ts`, `iHealth/Services/SocialDataService.swift`, `iHealth/Features/Home/FeedView.swift` |
| §2.12 Live workout recorder, §2.2 attest middleware, §2.11 launch bg + iPad clamp, §2.9 richer indexer + health | scope #4 | `iHealth/Features/Home/LiveRecorderView.swift`, `cloudflare/src/auth.ts`, `cloudflare/src/indexer.ts`, `iHealth/Assets.xcassets/LaunchBackground.colorset/` |
