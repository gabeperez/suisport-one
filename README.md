# SuiSport ONE

> **Train like a fighter.** Verified workouts, on-chain rewards, built for ONE Championship's Japanese audience.
>
> Hackathon submission — **Sui × ONE Samurai Tokyo Builders Arena**, April 2026.

## 🏯 Submission quick links

| | |
|---|---|
| **GitHub** | [`gabeperez/suisport-one`](https://github.com/gabeperez/suisport-one) |
| **Demo video** | _(speed-run script in [`DEMO_SPEEDRUN.md`](./DEMO_SPEEDRUN.md); upload URL added before submission)_ |
| **Cover image** | [`cover.html`](./cover.html) — open in Safari, screenshot the 1200×630 frame |
| **Live testnet** | Worker: `suisport-api.perez-jg22.workers.dev` · Move package: [`0x15c33f…2b2c`](https://suiscan.xyz/testnet/object/0x15c33f76fba3bc10a327d9792c7948e1eefd0162a13e7a0ac4774d7b8fec2b2c) |
| **Pitch outline** | [`PITCH.md`](./PITCH.md) (5-min slide-by-slide) |
| **Repo split context** | [`docs/REPO_SPLIT.md`](./docs/REPO_SPLIT.md)


SuiSport ONE turns ONE Championship fighters into your training partner. Pick a fighter, run their official fight-week camp inside the app, and prove every session on the Sui blockchain. Apple Watch verifies the workout, Walrus stores the canonical proof, the Move package mints SWEAT rewards and a soulbound trophy from that fighter on completion.

It's a fan-engagement product the moment ONE wants to ship it, and a real consumer app from day one.

| | |
|---|---|
| Hackathon | [Sui × ONE Samurai (Tokyo, Apr 2026)](https://mystenlabs.notion.site/sui-one-samurai-apr-2026-tokyo-builders-arena) |
| Demo day | Wed, April 29, 2026 — Ariake Arena, Tokyo |
| Track | Fan engagement / athlete tools — built around the live ONE Samurai 1 card |
| Stack | iOS (SwiftUI) · Cloudflare Workers + D1 + R2 · Walrus · Sui Move (testnet) · Apple App Attest · Enoki zkLogin |
| Repo | [`gabeperez/suisport-one`](https://github.com/gabeperez/suisport-one)

---

## The pitch in 60 seconds

ONE Championship has a global fighter roster, a passionate Japanese fan base, and one universal problem every league has: fans watch. They don't *do*. SuiSport ONE makes the gap between watching a fighter and training like one a single tap.

A fan opens the app the morning of ONE Samurai 1, sees Yuya Wakamatsu's pressure-camp pinned to the top of their feed, taps **Train with Yuya**, and starts logging the same striking + grappling + roadwork sessions the real Wakamatsu does. Apple Watch confirms each session was real. The Sui Move contract verifies the attestation, mints SWEAT tokens, and on completion drops a soulbound trophy NFT bearing Yuya's signature. The fighter's social handle, gym, and camp progress are all real — pulled from ONE Championship's public fighter pages. Photos are served live from `cdn.onefc.com` per their content syndication policy.

There's no wallet to install (Enoki zkLogin signs you in with Apple or Google), no gas to pay (sponsored transactions), and no complicated Japanese onboarding (the app is iOS-first, the largest mobile market in Japan).

---

## What's live

### iOS app (`iHealth/`)
- SwiftUI, iOS 17+, Apple HealthKit + App Attest + zkLogin
- Onboarding flow gates Health permission + age first, then auths via Apple, Google, or Sui wallet (Slush universal-link to Slush mobile)
- Five new fight-camp workout types — `striking`, `grappling`, `mma`, `conditioning`, `recovery` — alongside the existing run/ride/swim. HealthKit auto-classifies Apple Watch boxing/wrestling/martial-arts/mixed-cardio sessions
- ONE Samurai 1 hero card on the feed with a live countdown to fight night
- Real ONE Championship roster as seed athletes — Wakamatsu, Takeru, Nadaka, Ayaka Miura, Itsuki Hirata, Akimoto, Aoki, Wada — with bios, gyms, native handles, hotlinked CDN photos
- Real gyms as Clubs — Evolve MMA Singapore, Tribe Tokyo MMA, Team Vasileus, Eiwa Sports Gym, K-Clann
- Six fight-week camps as Challenges, all sponsored by ONE Championship
- On-chain workout submit with App Attest + canonical-hash, Walrus blob upload, Sui Move `submit_workout` call, deep links into Sui explorer + Walrus
- Push notifications via APNs (kudos, tips, comments) with `suisport://feed/<id>` deep links

### Backend (`cloudflare/`)
- Cloudflare Worker (Hono) + D1 + R2 + scheduled cron
- Worker fans out workout submissions to a multi-operator keypair pool on Sui testnet so we can mint `Workout` objects + SWEAT in parallel; reconciler cron retries any stuck submissions
- Trophy + PR writer runs on every workout submit (first-run, 5K/10K/half/full milestones, streaks, lifetime points)
- App Attest fully verifies — x5c chain → Apple App Attest Root CA, nonce extension, aaguid, credentialId — before any reward mints
- Apple Push Notifications via ES256 JWT, parallel fanout per device
- Avatar uploads via `POST /v1/media/avatar` to R2

### On-chain (`move/suisport/`)
- Sui Move package (testnet) with modules: `user_profile`, `workout_registry`, `rewards_engine`, `sweat`, `challenges`, `admin`, `version`
- Operator + Oracle separation — operator pays gas + owns user profile objects, oracle signs attestation digests the contract verifies. Compromise of one keypair doesn't drain the other
- Package: `0x15c33f76fba3bc10a327d9792c7948e1eefd0162a13e7a0ac4774d7b8fec2b2c` (testnet)

### Infra
- Worker: `https://suisport-api.perez-jg22.workers.dev`
- Wallet bridge (dapp-kit): `https://suisport-wallet.pages.dev`
- D1 database: `suisport-db` · R2 bucket: `suisport-media`
- Backend is shared with the canonical SuiSport repo — see `docs/REPO_SPLIT.md`

---

## Sui integration map

We build directly on the four Sui products the hackathon brief calls out:

| Product | Where we use it |
|---|---|
| **Sui Move** | `move/suisport/` — `rewards_engine::submit_workout` verifies an oracle-signed attestation digest, mints `WorkoutSubmitted` events, mints SWEAT to the athlete, optionally writes a soulbound `Trophy` NFT. Versioned shared `RewardsEngine` + `Version` objects |
| **Enoki zkLogin** | iOS `AuthService.signInWithGoogle/Apple` exchanges the OAuth id_token via the Worker → Enoki, returns a session JWT + Sui address. No seed-phrase UX |
| **Walrus** | `cloudflare/src/walrus.ts` uploads the canonical workout JSON (athlete, type, duration, distance, calories, blake2b digest) to a Walrus publisher and stores the resulting blob id back on the `Workout` object as immutable proof |
| **Slush wallet** | iOS `WalletConnectBridge` opens `https://my.slush.app/browse/<bridge-url>` so fans who already use Slush can sign in directly without ever copying a key |

We also leaned into App Attest end-to-end — every workout submission carries an Apple-attested signature so the rewards path is robust against jailbroken devices spoofing fake workouts.

The full deferred-Seal plan lives in `docs/SEAL_INTEGRATION.md`. (Short version: testnet key servers are non-durable and there's no Swift SDK, so we held off on Seal for this build.)

---

## How a fan actually uses it

```
1.  Fan opens SuiSport ONE the morning of ONE Samurai 1
2.  Hero card on feed: ONE Samurai 1 — 4 days out — Train for fight night
3.  Tap → fight-week camp screen, pick "Train with Yuya"
4.  Yuya's program shows: 14 sessions across 7 days,
    striking + grappling + roadwork mix
5.  Fan does session 1 (40 min striking), Apple Watch records,
    HealthKit hands the workout to SuiSport ONE
6.  App Attest signs the canonical hash, Walrus uploads the blob
7.  Worker submits to Sui via the operator keypair
8.  rewards_engine::submit_workout verifies oracle signature,
    mints WorkoutSubmitted + RewardMinted events, mints SWEAT
9.  iOS shows the live tx digest, links to Suiscan + Walruscan
10. On completion (14/14 sessions): soulbound Yuya trophy NFT
    + a kudos push from Yuya
```

The headline mechanic is intentionally narrow. We didn't invent a new social network for fighters — we made one round-trip between *watching ONE on TV* and *training like the fighter you just watched* feel like one product.

---

## What's in the repo

```
SuiSport ONE/
├── README.md                  ← you are here
├── PITCH.md                   ← 5-min pitch outline (problem → demo → impact)
├── DEMO.md                    ← 3-min demo video script + shot list
├── docs/
│   ├── ON_CHAIN_STRATEGY.md   ← operator fanout, retries, costs
│   └── SEAL_INTEGRATION.md    ← deferred-Seal plan
├── iHealth/                   ← SwiftUI app
│   ├── Features/Onboarding/   ← AgeGate → Auth → NameGoal → Health → Backfill → Notifs
│   ├── Features/Home/         ← Feed (with Samurai hero), Workout detail, Profile, Rewards
│   ├── Features/Clubs/        ← Gym membership UI
│   ├── Features/Explore/      ← Challenges (fight camps), Segments
│   ├── Services/              ← APIClient, HealthKit, Auth, App Attest, Push, Wallet bridge
│   └── Models/                ← Workout, Athlete, FeedItem, Challenge, etc.
├── cloudflare/
│   ├── src/                   ← Worker (Hono) + routes + Move client + APNs + Walrus
│   └── migrations/            ← D1 schema migrations 0001–0012
└── move/suisport/             ← Sui Move package (deployed on testnet)
```

---

## Running it locally

```bash
# 1. iOS
open iHealth.xcodeproj
# Cmd-R to a real device or simulator. Bundle id = gimme.coffee.iHealth.
# App Attest only fires on real devices; the simulator path uses unsigned mode.

# 2. Backend
cd cloudflare
npm install
npm run dev          # local Worker against the deployed D1
# Or:
npm run deploy

# 3. Move (only if you want to redeploy)
cd move/suisport
sui move build
sui client publish --gas-budget 100000000
# update SUI_PACKAGE_ID + related ids in wrangler secrets
```

Existing testnet deployment is live and shared with the canonical SuiSport repo. The Worker URL above already serves both apps — see `docs/REPO_SPLIT.md` for why.

---

## Brand & licensing

SuiSport ONE is an **independent hackathon submission**. ONE Championship has not endorsed, sponsored, or partnered with this project.

Fighter names, records, gym affiliations, and bios are factual public data sourced from [onefc.com](https://onefc.com) athlete pages, with cross-references to Sherdog and Tapology where helpful. Every fighter card carries a "Photo: ONE Championship" attribution; photos are loaded from `cdn.onefc.com` directly per ONE's [content syndication policy](https://www.onefc.com/content-syndication/) and never mirrored to our own storage.

If ONE Championship's team wants to pursue this concept further, all of the technical groundwork — verified-workouts pipeline, fighter-attached challenges, soulbound trophies — is here and we'd love to talk.

---

## Credits

Built by Gabe Perez for the Sui × ONE Samurai Tokyo Builders Arena.
With deep respect for the sport, ONE Championship, and the fighters whose camps we tried to honor in this small app.

📜 **Photo: ONE Championship.**
