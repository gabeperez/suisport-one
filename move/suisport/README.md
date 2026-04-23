# SuiSport Move Package

Six modules. Everything compiles against the `framework/mainnet` branch of
`sui-framework`. Move 2024 Edition.

## Modules

| Module | Purpose |
|---|---|
| `sweat` | Creates the `$SWEAT` fungible token via `coin::create_currency` + OTW. |
| `admin` | `AdminCap` (multisig-held) + `OracleCap` (backend signer pubkey, rotatable). |
| `version` | Shared `Version` object. Every entry function asserts version matches — upgrade-gated. |
| `user_profile` | Owned-per-user profile. Workouts attach via dynamic object fields. |
| `workout_registry` | Soulbound `Workout` struct (`key` only, no `store`). |
| `rewards_engine` | Shared object that owns `TreasuryCap<SWEAT>`. Verifies ed25519 attestations, enforces per-epoch + per-user caps, mints. |
| `challenges` | P2P escrow with deadline-based reclaim. |

## Build / test / deploy

```bash
# From within move/suisport
sui move build
sui move test
# Publish to testnet (adjust gas budget as needed)
sui client publish --gas-budget 200000000
```

After publish, record the returned `package_id`, then in a follow-up PTB:

1. Call `admin::mint_oracle(&AdminCap, oracle_pubkey)` → receive `OracleCap`.
2. Call `rewards_engine::initialize(&AdminCap, treasury, epoch_cap, per_user_cap, expected_version)`.
3. Transfer both `AdminCap` and `OracleCap` to their respective custody (multisig / HSM).

## Security

- `TreasuryCap<SWEAT>` never leaves `RewardsEngine` — minting is entirely gated by the on-chain ed25519 check + rate limits.
- Oracle key compromise = worst case `epoch_cap` drained per epoch until multisig pauses via `set_paused(true)`.
- Reward math uses `u64` throughout; reward amounts passed in by the oracle are
  bounded by `per_user_cap` (hard on-chain ceiling). Compute rewards server-side in `u128` if needed and pass the saturated `u64` value.
- `Workout` is `key`-only — genuinely soulbound.
- Upgrade path: `UpgradeCap` (returned at publish time) should be wrapped in a
  timelock object. Bump `version::value` when changing entry-function semantics.

## Audit plan

1. `sui move test --coverage` ≥ 90% on rewards + challenges.
2. Sui Prover specs for four invariants:
   - Total minted ≤ `epoch_cap × epochs_lived`.
   - Challenge conservation: sum of all payouts + reclaims = sum of all stakes.
   - `Workout` is non-transferable post-creation.
   - Nonce uniqueness: every `consumed_nonces` entry is monotonic.
3. Two parallel audits: MoveBit (formal) + OtterSec or Zellic (manual).
4. 30-day Immunefi public bounty on testnet.
5. Timelocked mainnet `UpgradeCap`.
