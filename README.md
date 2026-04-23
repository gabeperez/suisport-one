# SuiSport

A Strava-like fitness app on the Sui blockchain. Users sign in with Apple or
Google, record workouts via Apple HealthKit, and earn **Sweat Points** (which
can be converted to the $SWEAT token in a separate companion flow).

**Design principles**

- Zero crypto vocabulary in the UI. Users never see a wallet, seed phrase, or
  transaction. Sign-in with Apple is one tap and completes the full zkLogin
  flow invisibly. All gas is sponsored.
- HealthKit-first: we count what you already do and verify it before minting.
- Storage sovereignty: GPS traces and photos live on Walrus, owned by the
  user's Sui address.

## Repository layout

```
SuiSport App/
├── iHealth.xcodeproj/              # Xcode project (iOS 26+, Swift 6)
├── iHealth/                        # iOS app source
│   ├── iHealthApp.swift            # @main entry
│   ├── ContentView.swift           # RootView router
│   ├── AppState.swift              # @Observable app-wide state
│   ├── iHealth.entitlements        # HealthKit + App Attest + Sign in with Apple
│   ├── Assets.xcassets/
│   ├── DesignSystem/               # Theme, Typography, Haptics, Components
│   ├── Models/                     # User, Workout, SweatPoints, OnboardingStep
│   ├── Services/                   # AuthService (Enoki), HealthKit, Recorder, App Attest, APIClient
│   └── Features/
│       ├── Onboarding/             # 6-screen flow: Hero → Auth → Name/Goal → Health → Backfill → Notifications
│       └── Home/                   # RootTabView, Feed, Record sheet, Profile
├── move/suisport/                  # Move 2024 Edition package
│   ├── Move.toml
│   ├── sources/                    # sweat, admin, version, rewards_engine, workout_registry, user_profile, challenges
│   └── README.md
├── backend/                        # Fastify/TS service — Enoki + Walrus + App Attest + Sui sponsored tx
│   ├── package.json
│   ├── .env.example
│   ├── src/{index,config}.ts
│   ├── src/routes/{auth,workouts,health}.ts
│   ├── src/services/{enoki,walrus,oracle,sui,appAttest}.ts
│   └── README.md
└── README.md                       # You are here
```

## Getting the iOS app to build

Open `iHealth.xcodeproj` in Xcode 26.4 or newer. The project already uses
PBX file-system-synchronized groups, so everything under `iHealth/` is
automatically in the target — no drag-and-drop needed.

One-time Xcode setup (most already wired via build settings, but confirm in
**Signing & Capabilities** for the `iHealth` target):

1. **Signing**: select your Apple Developer team. The bundle id is
   `gimme.coffee.iHealth`.
2. **Capabilities** (+ button): add **HealthKit** (subfeature: Background
   Delivery), **App Attest**, and **Sign in with Apple**. The entitlements
   file is already referenced — Xcode will reconcile toggles with the file.
3. Build + run on a real iPhone (HealthKit + App Attest don't run in the
   simulator).

Notable build settings already set in `project.pbxproj`:
- `CODE_SIGN_ENTITLEMENTS = iHealth/iHealth.entitlements`
- All `NS*UsageDescription` strings as `INFOPLIST_KEY_*`
- `UIBackgroundModes = location processing`
- `IPHONEOS_DEPLOYMENT_TARGET = 26.4` (HealthKit workout stack on iPhone needs iOS 26)
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (Swift 6 main-actor-by-default)

## Running the Move package

```bash
cd move/suisport
sui move build
sui move test
sui client publish --gas-budget 200000000
```

After publish, paste the returned `package_id`, `AdminCap` id, and shared
object ids into `backend/.env`. Then:

1. Generate an Ed25519 key pair for the oracle (`sui keytool generate ed25519`)
   and paste the public key hex into the PTB that calls `admin::mint_oracle`.
2. Call `rewards_engine::initialize` with your `TreasuryCap<SWEAT>` and initial
   caps (`epoch_cap`, `per_user_cap`).
3. Transfer `AdminCap` to a Sui multisig. Transfer `OracleCap` to the backend's
   custodial address.

## Running the backend

```bash
cd backend
cp .env.example .env                    # fill in Enoki, Sui, oracle, Walrus values
npm install
npm run dev
```

The iOS app expects the backend at `APIClient.baseURL`
(`https://api.suisport.app`) — change that for local dev.

## What's real vs. what's mocked right now

| Piece | Status |
|---|---|
| Onboarding flow UI | Real SwiftUI, animated, haptic |
| Sign in with Apple UI | Real — calls `ASAuthorizationAppleIDProvider` |
| zkLogin exchange | Mocked in `AuthService` — derives a deterministic hex "address" from the OAuth subject so it looks + behaves like zkLogin will |
| HealthKit permission + backfill | Real — hits your phone's Apple Health |
| Live workout recording | Skeleton (`WorkoutRecorder`) wired but Record tab shows a picker sheet only |
| Feed / profile / points counters | Real, driven by backfilled workouts |
| Challenges tab | Placeholder |
| Move contracts | Real (Move 2024 Edition, compile target) — untested against mainnet yet |
| Backend | Scaffold — endpoint signatures + service stubs; Enoki/Walrus/App Attest logic marked `not implemented` where real API keys are needed |

## Next steps to go from demo to testnet-live

1. Wire a real backend `POST /auth/session` that calls Enoki's HTTP API — swap the mock in `AuthService` for `APIClient.exchange`.
2. Implement `services/sui.ts::submitWorkoutPTB` (Mysten TS SDK + Enoki sponsored-tx).
3. Wire App Attest registration on first launch; send the attestation blob to the backend before any submits.
4. Build out the live workout UI (`Features/Record`) around `WorkoutRecorder`.
5. Publish the Move package to testnet; run `rewards_engine::initialize`.
6. End-to-end: record a workout → backend verifies → Walrus upload → Sui mint → feed updates with verified check.
