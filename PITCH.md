# SuiSport ONE — pitch outline

**5 minutes pitch + up to 4 minutes Q&A. Maximum 9 minutes per the handbook.**

Hackathon: Sui × ONE Samurai Tokyo Builders Arena.
Judging weights: Innovation 30 · Practical Impact 30 · Technical 30 · Pitch 10.

The deck is built for a non-Japanese-speaking ONE rep on the panel and a Sui-native crew. English. Concrete. Show the running app in the second half — words first, demo last.

---

## Slide 1 — Title (15s)

```
SuiSport ONE
Train like a fighter.

Verified training. On-chain rewards. Built for ONE Championship.
Sui × ONE Samurai Tokyo Builders Arena · April 2026
Gabe Perez · @gabeperez
```

Voiceover beat: "Hi, I'm Gabe. SuiSport ONE turns ONE Championship fighters into your training partner. Verified by your Apple Watch, rewarded on Sui."

---

## Slide 2 — The problem (45s)

> Every league has the same gap. Fans watch. They don't *do*.

- ONE has a global roster of fighters and a Japanese audience that loves the sport
- The deepest engagement loop today is: watch the fight, follow on Instagram, buy a t-shirt
- There's no product that lets a fan **train like the fighter** with a way to prove it

Two stat hits to ground the audience:

- 80% of Japan's mobile users are on iOS — Apple Watch + HealthKit + zkLogin is a native-feel stack here
- Strava has 100M+ users; Nike Run Club has 50M+. Fitness logging is a habit; what's missing is the *fighter-attached* product

**Voiceover:** "Watching a fighter is passive. Training like one is the deepest possible engagement. Nobody has built that round-trip — until now."

---

## Slide 3 — The solution (45s)

```
Pick a fighter. Run their camp. Prove every session.
The chain mints rewards. The fighter's trophy lands in your wallet.
```

Three rows on the slide, with screenshots:

| 1. Open the app | 2. Train | 3. Prove |
|---|---|---|
| ONE Samurai 1 hero card. Tap "Train with Yuya." | Apple Watch records the session. App Attest signs the canonical hash. | Walrus stores the blob, Sui mints the proof. Soulbound trophy on completion. |

**Voiceover:** "On the morning of ONE Samurai 1, a fan opens SuiSport ONE and sees Yuya Wakamatsu's pressure-camp pinned to the top. They tap, do the same striking + grappling + roadwork sessions Yuya does, and on completion get a soulbound trophy NFT from Yuya. Sui makes it real, App Attest makes it honest, Walrus makes it permanent."

---

## Slide 4 — Sui integration map (60s)

> Show the panel exactly which Sui products you used.

```
┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐
│ Apple Watch /    │    │ Cloudflare       │    │ Sui Move         │
│ HealthKit        │───▶│ Worker + D1      │───▶│ rewards_engine   │
│  + App Attest    │    │  + Walrus blob   │    │  ::submit_workout│
└──────────────────┘    └──────────────────┘    └────────┬─────────┘
        ▲                                                 │
        │                                                 ▼
        │                                       SWEAT mint + Trophy NFT
   Enoki zkLogin                                        │
   (Apple/Google)                                        ▼
                                                  Walruscan + Suiscan
```

| Sui product | Where it shows up |
|---|---|
| **Sui Move** | `rewards_engine::submit_workout` — verifies oracle digest, mints SWEAT, emits events |
| **Enoki zkLogin** | Apple/Google → Sui address. No seed phrases |
| **Walrus** | Canonical workout JSON, immutable proof |
| **Slush** | Universal-link sign-in for fans who already have a wallet |
| **App Attest** | Full x5c chain + nonce + aaguid verification end-to-end |

**Voiceover:** "Every product the brief mentioned is in this build. Move handles the contract. Walrus stores the proof. Enoki does the wallet-less sign-in. Slush is one tap away for fans who already have a wallet. And App Attest closes the gap a normal fitness app would leave open — we don't trust the phone, we trust Apple's hardware."

---

## Slide 5 — Live demo (3 min, narrated)

Switch to the device. **DEMO.md** has the shot list. The 3-minute path:

1. Onboard (12s) — AgeGate → Apple sign-in → no seed phrase
2. Hero card (8s) — Samurai 1 countdown
3. Open camp (10s) — Yuya's 14-session program
4. Submit a workout (40s) — record, hit save, watch the chain mint
5. Tx confirmation (15s) — tap into Suiscan + Walruscan from inside the app
6. Trophy view (15s) — show the soulbound trophy on the profile
7. Push notification (15s) — kudos from another fighter, deep-link back
8. Featured Fighter profile (30s) — Yuya's page with real bio + photo + camp progress + ONE Championship attribution
9. Wallet sign-in fallback (15s) — Slush universal-link round trip

If demo time runs short, drop steps 6 and 9 — they're verification of features the judges can read about in the README.

---

## Slide 6 — Impact + Future (45s)

Why this matters beyond the hackathon:

- **For ONE:** new revenue line (paid camps), measurable fan engagement, on-chain audit trail of who actually trained vs. who just watched
- **For fighters:** royalty on every camp completion, soulbound trophies that double as fan badges, no middleman — the contract pays them directly
- **For Sui:** a flagship consumer use case that exercises Move + Enoki + Walrus + Slush in one product, with a path to mainnet

What's next (if you'll have us):

1. **Mainnet deployment** with multi-operator fanout (already coded, gated behind a single env flag)
2. **Seal-encrypted private camps** — pay-per-view fighter programs, decryptable only after a Move-policy gate (`docs/SEAL_INTEGRATION.md` has the design ready to go)
3. **In-app PPV** — a buy-the-fight flow next to the camp ("Train with Yuya, then watch him fight live")
4. **Japanese localization beyond the headlines** — the iOS bones already understand the locale; just need the strings

**Voiceover:** "We didn't build a new social network. We built one round-trip — *watch the fighter → train like them → prove it on chain* — and made it feel native."

---

## Slide 7 — Close (15s)

```
SuiSport ONE
Code: github.com/gabeperez/suisport-one
Demo:  [hosted video link]
Try:   suisport-api.perez-jg22.workers.dev (testnet)

Train like a fighter.
Photo: ONE Championship.
```

Then sit down for Q&A.

---

## Likely Q&A — answers to rehearse

**Q: Why ONE and not UFC / PFL?**
ONE has a Japanese fight night this week, a championship-grade roster of Japanese fighters (Wakamatsu, Takeru, Nadaka, Hirata), and a brand identity built around honor + craft that maps cleanly to a "train like a fighter" UX. The hackathon brief is also literally ONE-themed.

**Q: Have you talked to ONE Championship?**
Not yet. This is an independent submission. Every fighter cited is on their public roster page; every photo is hotlinked from their CDN per their content-syndication policy; we'd be excited to talk if there's interest.

**Q: How does the contract know the workout is real?**
Three layers. (1) Apple HealthKit hands us a `HKWorkout` from the Watch. (2) App Attest signs the canonical hash with the Secure Enclave — the cert chain verifies all the way back to Apple's App Attest Root CA. (3) An off-chain oracle keypair signs the digest the Move contract checks. A jailbroken device can't fake step 2; a compromised oracle can't fake step 3 alone. Both have to fail to mint a fake SWEAT.

**Q: Why testnet?**
Hackathon constraint, and Seal's mainnet committee is "available soon" per Mysten's docs. Mainnet is a single env flag away — the multi-operator keypair fanout, retry reconciler, and oracle separation are already in.

**Q: What does the user actually own?**
Their `UserProfile` Sui object, every `Workout` object minted from their submissions, the SWEAT they earn, and the soulbound trophy NFTs from completed camps. Sui addresses are derived through zkLogin so the user doesn't manage a key — the profile follows them across devices.

**Q: How does ONE / a fighter get paid?**
Today: zero. This is hackathon scope — show the loop works. Mainnet path: Move-level royalty split on `submit_workout` mints when the workout is part of a fighter-sponsored camp. Trophy mints can also carry a 5% creator royalty payable to the fighter's address.

**Q: How does this scale?**
Cloudflare Worker + D1 + R2 + Walrus is horizontally scalable on day one. The Sui throughput bottleneck is the operator keypair pool; we already implemented multi-operator fanout (`SUI_OPERATOR_KEYS` comma-list) so we can add operator capacity without contract changes. Sponsored transactions are next on the list.
