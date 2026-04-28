# SuiSport ONE — Demo Day Brief

> **Sui × ONE Samurai Tokyo Builders Arena · Top 10 · Wed Apr 29, 2026 · Ariake Arena**
>
> Format: 5 min pitch + up to 4 min Q&A · max 9 min · English · scored async per judge.
> Judging weights: **Innovation 30 · Practical Impact 30 · Technical 30 · Pitch 10**.

This is the master brief I'm taking on stage. It rolls up the pitch, the technical
substrate, the live testnet artefacts, and a long list of likely Q&A — split for the
two audiences in the room: a Sui-native developer panel and a non-Japanese-speaking
ONE Championship rep.

---

## 0 · The 30-second answer

> SuiSport ONE turns ONE Championship fighters into your training partner.
> Pick a fighter, run their official fight-week camp, and prove every session
> on Sui. Apple Watch verifies it. Walrus stores the proof. Move mints SWEAT
> rewards and a soulbound trophy from that fighter when you finish their camp.
> No wallet to install, no gas, no seed phrase — and a real path to mainnet.

If I get cut to one sentence: **"It's the round-trip between watching a fighter
on TV and training like one — verified by your Apple Watch and minted on Sui."**

---

## 1 · Why we win each criterion

### Innovation (30%)

- **The category is new.** "Train like a fighter, prove it on chain, get the fighter's
  trophy" is a product, not a feature. Strava verifies effort; we verify *which fighter's
  camp you ran*. Soulbound trophies signed by the fighter are the artifact.
- **App Attest end-to-end** — every workout is signed by the iPhone Secure Enclave with
  the full x5c chain, nonce extension, aaguid, and credentialId verified all the way back
  to Apple's App Attest Root CA. This is uncommon in fitness web3 — most "move-to-earn"
  apps trust the phone. We don't.
- **Repetition decay anti-grinding** — written into the Move contract itself, not the
  backend. A fighter mixing striking + grappling + roadwork keeps full rewards; someone
  logging the same treadmill walk six times in a day decays to 50%. The contract
  mechanically rewards the *shape* of a real fight camp.
- **Transparent on-chain formula.** The reward isn't "look at the digest the server
  sent." The contract recomputes the reward from the *signed components*, so the
  off-chain server can't lie about the math — only about the inputs. Every mint emits
  a `WorkoutScored` event with the full breakdown.

### Practical Impact (30%)

- **Live testnet, working today.** Two real on-chain mints already (digests in §6).
  Worker URL is public. App is buildable from the public repo right now.
- **Real audience match.** 80%+ of Japan's mobile users are on iOS — App Attest +
  HealthKit + zkLogin is the native stack here. ONE has a championship-grade Japanese
  roster. The hackathon is themed around their next card.
- **Real revenue path** for ONE: paid camps (PPV-adjacent), royalty on every camp
  completion, on-chain audit of who actually trained vs. who just watched. Soulbound
  trophies that double as fan badges keep the fighter — not the platform — at the
  centre of the loyalty loop.
- **Mainnet is one env flag away.** Multi-operator fanout, retry reconciler, oracle
  separation, mainnet audit punch list, and migration plan are all in `docs/`.

### Technical Implementation (30%)

- **Every Sui product the brief named is in the build:** Move, Enoki zkLogin, Walrus,
  Slush wallet. Plus App Attest as a hardware trust root.
- **Production-grade Move package** — versioned, paused-able, oracle-separated,
  capped per-tx + per-user-epoch + per-global-epoch, replay-protected via
  consumed-nonces table, on-chain formula recomputation, two-event emission
  (headline + rich) for back-compat indexers.
- **Operator/oracle separation by design.** Operator pays gas + owns user profiles.
  Oracle signs attestation digests. **A leak of either alone can't drain the contract.**
- **Real backend, not a mock.** Cloudflare Worker (Hono) + D1 + R2 + Walrus + APNs +
  Sui SDK + scheduled cron reconciler. Multi-operator keypair pool means we can scale
  Sui throughput without touching the contract.

### Pitch (10%)

- **English first.** Aimed at the ONE rep who isn't a Japanese speaker.
- **Concrete, not abstract.** Real fighters, real gyms, real photos, real testnet
  mints, real CDN attribution.
- **Show the running app.** Half the time is live demo, narrated. Backup video on
  USB just in case.

---

## 2 · The 5-minute pitch (rehearsed)

Source-of-truth deck plan: [`PITCH.md`](./PITCH.md). Below is the time-coded version
I'm running on stage. Aim for 4:45 to leave a polite buffer.

| Time | Slide | Beat |
|---|---|---|
| 0:00 – 0:15 | Title | "Hi, I'm Gabe. SuiSport ONE turns ONE Championship fighters into your training partner. Verified by your Apple Watch, rewarded on Sui." |
| 0:15 – 1:00 | Problem | Every league has the same gap — fans watch, they don't *do*. ONE has the roster + audience but no train-like-them product. |
| 1:00 – 1:45 | Solution | "Pick a fighter. Run their camp. Prove every session." Three-row screenshot strip. |
| 1:45 – 2:45 | Sui integration map | Walk the diagram. Move + Enoki + Walrus + Slush + App Attest, one sentence each. |
| 2:45 – 4:15 | Live demo | Onboard → hero card → submit a workout → tx confirmation in-app → trophy view. Narrated. |
| 4:15 – 4:45 | Impact + future | Mainnet flag is ready. Seal-encrypted PPV camps next. ONE revenue line. |
| 4:45 – 5:00 | Close | "Train like a fighter. Photo: ONE Championship." Sit down for Q&A. |

Demo shot list: [`DEMO.md`](./DEMO.md). Speed-run cheat sheet: [`DEMO_SPEEDRUN.md`](./DEMO_SPEEDRUN.md).

---

## 3 · The product, one screen at a time

| Screen | What it does | Why a judge should care |
|---|---|---|
| **AgeGate** | First-class step *before* sign-in. iOS app stores DOB + age check. | Required for HealthKit + Apple ID compliance. Most web3 apps skip this. |
| **Auth** | Three providers as siblings: Apple, Google (zkLogin), Sui Wallet (Slush universal-link). Last-used provider is promoted on return. | Zero seed-phrase UX. zkLogin handles 99% of users; Slush is one tap for crypto-native fans. |
| **Hero card** | ONE Samurai 1 countdown pinned to the top of the feed. | Tied to a real ONE event the judges are at. |
| **Camp picker** | Six fight-week camps, all sponsored by ONE Championship in the metadata. Yuya Wakamatsu's pressure-camp leads. | Real fighter, real bio, real gym, real CDN photo. |
| **Recorder / upload** | Two paths — "Upload a past Apple Health workout" or "Record a new session." Web2 voice; on-chain proof is small print. | Honest UX: chain is plumbing, not theatre. |
| **Tx confirmation** | Inline links to Suiscan + Walruscan from the workout detail. | Receipts, not vibes. |
| **Trophy view** | Soulbound NFT minted on camp completion, signed metadata from the fighter. | The artifact a fan keeps. |
| **Profile / Rewards** | SWEAT balance, bonus breakdown, streak counter. | Reads the rich `WorkoutScored` event so each mint is auditable. |

---

## 4 · Architecture at a glance

```
┌──────────────────┐    ┌──────────────────────┐    ┌──────────────────────────┐
│ Apple Watch /    │    │ Cloudflare Worker     │    │ Sui Move (testnet)       │
│ HealthKit        │───▶│  + Hono + D1 + R2     │───▶│ rewards_engine::         │
│  + App Attest    │    │  + Walrus publisher   │    │   submit_workout         │
└──────────────────┘    │  + APNs JWT push      │    │                          │
        ▲               │  + Sui operator pool  │    │ → SWEAT mint             │
        │               │  + cron reconciler    │    │ → Workout NFT (soulbound)│
        │               └──────────────────────┘    │ → Trophy NFT on completion│
        │                                            │ → WorkoutScored event    │
   Enoki zkLogin                                     └──────────────────────────┘
   (Apple / Google)                                            │
                                                                ▼
                                                       Suiscan + Walruscan deep links
```

Layers, plain English:

1. **iOS** records the workout via HealthKit, signs the canonical hash with App Attest,
   uploads to the Worker.
2. **Worker** verifies App Attest end-to-end (cert chain back to Apple's root, nonce,
   aaguid). Uploads the canonical JSON to Walrus. Builds the attestation digest. Signs
   it with the oracle keypair. Picks a free operator keypair from the pool. Calls
   `submit_workout` on Sui.
3. **Move contract** verifies the oracle signature, recomputes the reward from the
   signed components, enforces caps, mints SWEAT to the athlete, mints the soulbound
   `Workout` proof object, emits two events.
4. **Worker cron** reconciles any stuck submissions on the next run.
5. **iOS** subscribes to events / polls digests, shows tx + Walrus links inline.

---

## 5 · The Move contract in 90 seconds

Package: `0x15c33f76fba3bc10a327d9792c7948e1eefd0162a13e7a0ac4774d7b8fec2b2c`
([Suiscan](https://suiscan.xyz/testnet/object/0x15c33f76fba3bc10a327d9792c7948e1eefd0162a13e7a0ac4774d7b8fec2b2c))

Modules: `user_profile`, `workout_registry`, `rewards_engine`, `sweat`, `challenges`, `admin`, `version`.

**Reward formula (basis points; 10000 = 1.0×):**

```
multiplier_bps = 10000
               + 2500 if pr_bonus            (beat a personal record)
               + 5000 if challenge_bonus     (counts toward an active fight camp)
               + 2000 if first_time_bonus    (first workout of this type ever)
               + min(streak_days * 200, 5000)   (+2%/day, capped at +50%)

reward = base_reward × multiplier_bps / 10000
                    × repetition_decay_bps / 10000
reward = min(reward, MAX_REWARD_PER_TX)        // 5,000 SWEAT × 1e9
```

`repetition_decay_bps` is signed by the oracle and clamped on-chain to [5000, 10000].

**Defense in depth:**

| Layer | What it catches |
|---|---|
| `version::assert_matches` | Stale clients calling deprecated package versions |
| `paused` flag | Emergency stop |
| `OracleCap.revoked` | Oracle key rotation without redeploy |
| `expires_at_ms` check | Replay of stale attestations |
| ed25519 signature on canonical digest | Backend-key compromise (only one) |
| Consumed-nonces table | Single-use attestation enforcement |
| On-chain formula recomputation | Server lying about the math |
| `MAX_REWARD_PER_TX` ceiling | Worst-case single mint |
| `epoch_cap` + `per_user_cap` | Bounded blast radius if oracle leaks |

**Two events per mint:**

- `RewardMinted { athlete, amount, epoch }` — flat, indexer-friendly, back-compat.
- `WorkoutScored { athlete, workout_type, base_reward, pr_bonus, challenge_bonus,
  first_time_bonus, streak_days, repetition_decay_bps, multiplier_bps, final_reward, epoch }`
  — every formula component, so explorers can reconstruct *why* a particular mint happened.

---

## 6 · Live testnet artefacts

Showable / linkable on stage:

- **Move package:** `0x15c33f76fba3bc10a327d9792c7948e1eefd0162a13e7a0ac4774d7b8fec2b2c`
- **Worker (public):** `https://suisport-api.perez-jg22.workers.dev`
- **Wallet bridge (dapp-kit):** `https://suisport-wallet.pages.dev`
- **D1:** `suisport-db` · **R2:** `suisport-media`
- **Two real on-chain mints** — digests ready to drop in Q&A: `2y6k6ucu…` and `FYusVDGW…`
- **GitHub:** `gabeperez/suisport-one` (public, scrubbed of fork mentions)

If asked to prove anything mid-pitch: open Suiscan to the package address and scroll
to the most recent `WorkoutScored` event. The whole formula is right there.

---

## 7 · Anticipated Q&A

Tone-check: be confident, never defensive. Concede a real limit cleanly when there is
one (testnet, hackathon scope, no signed ONE deal). Don't oversell.

### 7a · Developer-crowd questions (Sui-native panel)

**Q: How does the contract know the workout is real?**
> Three layers. (1) Apple HealthKit hands us a `HKWorkout` from the Watch. (2) App
> Attest signs the canonical hash with the Secure Enclave — we verify the full x5c
> chain back to Apple's App Attest Root CA, plus the nonce extension, aaguid, and
> credentialId server-side. (3) An off-chain oracle keypair signs the attestation
> digest the Move contract checks. A jailbroken device can't fake step 2; a
> compromised oracle alone can't fake step 3 in a way that mints unbounded SWEAT
> because we cap per-tx, per-user-epoch, and per-global-epoch.

**Q: Why both an oracle signature *and* operator keypair? Aren't you just signing twice?**
> They serve different threats. The operator pays gas and owns the user profile
> objects. The oracle signs the attestation the contract verifies. Compromise of
> the operator keypair drains gas; compromise of the oracle keypair lets you forge
> *one* mint up to the per-tx cap. Both have to fail to drain the treasury — that's
> the threat model the caps assume.

**Q: Why recompute the reward on-chain instead of trusting the oracle's number?**
> Smaller blast radius if the oracle key leaks. The signed digest covers every
> *input* — base reward, bonus flags, streak count, decay — but not the derived
> output. The contract computes the multiplier itself. That means the off-chain
> server can lie about the inputs (and we cap that to per-tx + per-user-epoch
> ceilings), but it cannot lie about the math.

**Q: Why testnet?**
> Hackathon constraint, plus Seal's mainnet committee is "available soon" per
> Mysten's docs and we have a Seal-encrypted PPV-camp design we'd want to deploy
> day-one on mainnet. Mainnet is a single env flag away — multi-operator fanout,
> retry reconciler, oracle separation, and the audit punch list are all done. See
> `docs/MAINNET_AUDIT.md` and `docs/MAINNET_MIGRATION.md`.

**Q: What scales when this hits 10,000 users? 100,000?**
> The Sui throughput bottleneck is the operator keypair pool. We already implemented
> multi-operator fanout — `SUI_OPERATOR_KEYS` is a comma-list, the Worker picks a
> free one per submission. Adding capacity is "rotate one secret, redeploy." Cloudflare
> Worker + D1 + R2 + Walrus is horizontally scalable on day one. Sponsored
> transactions are next on the list.

**Q: What happens if a mint fails after the user already saw "submitting"?**
> Worker has a scheduled cron reconciler that picks up stuck submissions. The user
> sees a pending state, retries are idempotent because the attestation nonce is
> single-use — you can't double-mint, you can only succeed or fail.

**Q: Did you actually use Walrus, or just call it "Walrus"?**
> Real Walrus publisher. The canonical workout JSON — athlete, type, duration,
> distance, calories, blake2b digest — gets uploaded, the blob ID gets stored on
> the on-chain `Workout` object as immutable proof, and we deep-link into Walruscan
> from the workout detail in-app.

**Q: zkLogin handles which providers?**
> Apple and Google end-to-end via Enoki. Apple's the priority for Japan because of
> iOS share. Google is on by default for fans signing in from non-Apple devices.
> Slush is the third option for crypto-native users — universal-link to
> `my.slush.app/browse/<bridge-url>`, dapp-kit handles the wallet enumeration.

**Q: Apple App Attest — full implementation or stub?**
> Full. x5c chain → App Attest Root CA, nonce extension, aaguid, credentialId — all
> verified server-side before any reward path runs. Simulator path is unsigned-mode
> only and bypasses minting; real-device App Attest is enforced.

**Q: Why a soulbound trophy and not a transferable one?**
> The trophy is a *proof of completion* tied to *that fan's* training. Making it
> transferable would let someone buy completion. The whole point is: you trained,
> the fighter signed off, you got the trophy. Personal record, not a collectible
> in the speculation sense.

**Q: How much gas per workout?**
> Order of a few mSUI per submit on testnet — the operator keypair pool absorbs it
> on the user's behalf. On mainnet we'd swap in sponsored transactions so the user
> never sees a gas line item.

**Q: What's in the rich `WorkoutScored` event vs. the headline `RewardMinted`?**
> `RewardMinted` is the flat one — athlete, amount, epoch — kept for back-compat
> with indexers and explorer subscribers. `WorkoutScored` carries every formula
> component so an indexer can build leaderboards filtered by bonus type, run fraud
> audits, and the in-app rewards screen can show the per-component breakdown.

**Q: Why not Solana / Base / Aptos?**
> Sui's object model maps cleanly to "a workout is a thing the user owns." Move's
> resource model makes the soulbound trophy a one-line type. zkLogin is the cleanest
> walletless on-ramp on any chain right now. Walrus is the only first-class blob
> store on a major L1. And the hackathon is Sui-themed.

**Q: What's the indexing story?**
> We emit two events per mint by design. Any standard event indexer (Sui Indexer,
> Subsquid-style ingestion, our own D1 cache) can subscribe and reconstruct state.
> The rich event makes the explorer the indexer for casual viewers.

**Q: How big is the Move package?**
> Seven modules, ~14KB on the rewards engine. `submit_workout` is the only
> entrypoint a user touches; everything else is admin/setup or pure helpers.

### 7b · Sports / business / ONE Championship questions

**Q: Have you talked to ONE Championship?**
> Not yet. This is an independent submission. Every fighter cited is on their public
> roster page; every photo is hotlinked from `cdn.onefc.com` per their content
> syndication policy and never mirrored to our own storage; every card carries the
> required "Photo: ONE Championship" attribution. We'd be excited to talk if there's
> interest from their team.

**Q: Why ONE and not UFC / PFL / Bellator?**
> ONE has a Japanese fight night this week, a championship-grade roster of Japanese
> fighters — Wakamatsu, Takeru, Nadaka, Hirata — and a brand identity built around
> honor and craft that maps cleanly to a "train like a fighter" UX. The hackathon
> brief is also literally ONE-themed.

**Q: How does the fighter actually get paid?**
> Hackathon scope: zero. We wanted to prove the loop works without baking in numbers
> we'd have to negotiate with ONE later. Mainnet path: a Move-level royalty split
> on `submit_workout` mints when the workout is part of a fighter-sponsored camp,
> plus a 5% creator royalty on trophy mints payable to the fighter's address. Both
> are contract-level — the fighter doesn't trust the platform, they trust the chain.

**Q: How does *ONE* make money?**
> Three lines, in order of how soon they ship. (1) Sponsored fight camps as a paid
> fan tier — fans pay ONE to unlock the premium fighter's camp content. (2) On-chain
> audit of who actually trained vs. who watched — sponsorship gold. (3) PPV bundling:
> "Train with Yuya for 14 days, then watch him fight live" as a single $X package.
> Seal-encrypted private camps make (1) and (3) tamper-proof.

**Q: What does the user actually own?**
> Their `UserProfile` Sui object, every `Workout` object minted from their submissions,
> the SWEAT they earn, and the soulbound trophy NFTs from completed camps. The Sui
> address is derived through zkLogin so the user doesn't manage a key — the profile
> follows them across devices.

**Q: SWEAT — is it a token? A point? Something I can sell?**
> Functionally a fungible reward token on Sui — it's actually a `Coin<SWEAT>` minted
> via a `TreasuryCap`. Whether it's tradable is a governance + regs question that
> belongs at mainnet, not at the hackathon. Today: in-app utility currency. Tomorrow:
> at ONE's discretion.

**Q: Won't people just cheat? Run on a treadmill while watching Netflix?**
> They can — but the contract knows. Repetition decay is hard-coded: the second
> identical session in a 24-hour window mints 90% of base, the third 80%, floored
> at 50%. A real fight camp mixes striking + grappling + roadwork + recovery — that
> shape stays at full reward. Six identical treadmill walks taper hard. We reward
> the *shape* of training, not just the volume.

**Q: What about fans who don't own an Apple Watch?**
> The Watch is the sharpest signal but not the only one. Apple Health on iPhone alone
> still produces an `HKWorkout` for many activity types. We support the full HealthKit
> roster — running, cycling, swimming, plus five new combat-focused types: striking,
> grappling, MMA, conditioning, recovery. Android is post-hackathon.

**Q: Why iOS first?**
> 80%+ of Japan's mobile users are on iOS, and the hackathon's audience is Japan.
> App Attest is also the strongest hardware-attested signal we have for "this came
> from a real device" — Android Play Integrity is roughly equivalent and is on the
> mainnet roadmap.

**Q: How is this different from Stepn / Sweatcoin / Strava?**
> Strava verifies *effort*, doesn't tie to a fighter, no chain. Sweatcoin treats
> walking as a token mine, no athlete attachment. Stepn requires sneaker NFTs and
> got hammered when the speculation collapsed. Our hook is the fighter — *the
> fighter's camp, the fighter's signature, the fighter's trophy.* Take the fighter
> away and the product doesn't exist; that's what makes it ONE-shaped.

**Q: What if a fighter doesn't want to be in the app?**
> The trophy mint requires a fighter-controlled key signing off — without that
> consent, no trophy. Hackathon build uses our keys for demo fighters as a stand-in.
> Production version: each onboarded fighter has their own keypair (or zkLogin) and
> signs trophy mints from a fighter-portal app. Opt-in by design.

**Q: Privacy — what's stored where?**
> On chain: a workout *digest* (hash + duration + type + reward) and a Walrus blob
> ID. Not GPS traces, not heart rate, not anything personally identifying about the
> route or session. The Walrus blob is the canonical workout JSON; we control what
> goes in it and we strip identifying data before upload. Privacy policy lives at
> `legal/PRIVACY.md`.

**Q: How long until ONE could ship this?**
> The honest answer: 4–8 weeks of integration with ONE's content team to license
> the camps and onboard fighter keys, plus the mainnet flip we already have planned.
> The technical surface is done.

### 7c · General / mixed Qs that could come from either crowd

**Q: What's the one thing you'd add tomorrow if you won?**
> Seal-encrypted private camps. The plan is in `docs/SEAL_INTEGRATION.md`. It turns
> camps into actual PPV — the camp content is encrypted, the decryption key is
> released by a Move-policy gate after payment lands. Today's "free for everyone"
> camp becomes a tiered product on mainnet day one.

**Q: What surprised you while building?**
> How much honesty the App Attest path forces on you. Most fitness apps trust the
> phone, then bolt on auditing later. Once you make the Secure Enclave the trust
> root, everything downstream — the oracle, the Move caps, the events — has to
> agree. It's a stricter design but the result is a system where *no single
> compromise mints fake SWEAT*.

**Q: What broke during the hackathon?**
> Two things worth naming. Slush deep-link routing took longer than we expected
> because the universal-link pattern is documented across two repos. And we had a
> "TypeMismatch on submit_workout arg 3" the first day after a contract redeploy —
> turned out we'd reused an old `UserProfile` object from the previous package.
> Cleared the cached row, retry succeeded. Both shipped.

**Q: What would you do differently?**
> Pick a smaller fighter roster for v1 and go deeper on each one — full video,
> real workout structure from the fighter's actual camp, fighter-signed welcome
> messages. Right now the breadth is hackathon-broad. ONE's value is in the
> fighters; the deeper we go on each one, the more the product earns its name.

---

## 8 · Demo backup plan

Live demo > video. But have both ready.

| Failure | Backup |
|---|---|
| WiFi at venue is bad | Pre-recorded 3-min demo video on USB stick + on phone (airdrop-ready) |
| Sui testnet is slow / RPC degraded | Skip the live mint, show a previous tx digest on Suiscan from the browser |
| App crashes mid-demo | Restart, keep narrating; if it crashes twice, pivot to video |
| Walrus publisher is down | Show an existing blob ID resolved on Walruscan from the browser |
| Slush universal link doesn't open Slush | Tap "Use another Sui wallet" — opens the dapp-kit page in Safari, ConnectButton enumerates whatever wallets the browser has |
| Projector adapter doesn't fit | Bring USB-C-to-HDMI + Lightning-to-HDMI; venue has HDMI cable + projector |

**Ten minutes early on stage to set up.**

---

## 9 · Power lines to drop in Q&A

When you need a snappy close, pick one:

- *"We don't trust the phone. We trust Apple's hardware."*
- *"The contract pays the fighter. There's no platform middleman."*
- *"It's the round-trip between watching a fighter on TV and training like one."*
- *"Mainnet is a single env flag away."*
- *"We didn't build a new social network for fighters. We made the gap between
  watching one and training like one feel like one product."*

---

## 10 · One-page leave-behind

If a judge asks "what should I read after this?", in priority order:

1. `README.md` — what's live, what's where
2. `PITCH.md` — the 5-min slide-by-slide
3. `move/suisport/sources/rewards_engine.move` — the contract, with comments
4. `docs/MAINNET_MIGRATION.md` — the path to production
5. `docs/SEAL_INTEGRATION.md` — what we'd ship next

GitHub: `gabeperez/suisport-one`

---

📜 **Photo: ONE Championship.**
