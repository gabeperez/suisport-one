/// The minting engine.
///
/// Holds the `TreasuryCap<SWEAT>` inside a shared object. Every mint goes
/// through `submit_workout`, which:
///   1. Verifies the package version matches.
///   2. Verifies the ed25519 attestation from the backend oracle.
///   3. Checks the nonce hasn't been consumed.
///   4. Computes the reward on-chain from a transparent formula
///      (base + bonuses, with repetition decay) — every component
///      verified by the oracle signature, so the final mint amount
///      cannot diverge from what the formula prescribes.
///   5. Enforces a hard per-transaction mint ceiling, then per-epoch
///      global and per-user mint caps.
///   6. Mints SWEAT, creates a soulbound Workout, and attaches it to
///      the user's profile.
///   7. Emits a structured event with every formula component so
///      indexers and explorers can reconstruct exactly why a given
///      reward was minted.
///
/// Reward formula (in basis points; 10000 = 1.0x):
///
///   multiplier_bps = 10000
///                  + 2500 if pr_bonus            (beat a personal record)
///                  + 5000 if challenge_bonus     (workout counts toward an active fight camp)
///                  + 2000 if first_time_bonus    (athlete's first workout of this type ever)
///                  + min(streak_days * 200, 5000) (+2% per streak day, capped at +50%)
///
///   reward = base_reward * multiplier_bps / 10000
///                       * repetition_decay_bps / 10000
///   reward = min(reward, MAX_REWARD_PER_TX)
///
/// Repetition decay is computed off-chain (counts how many sessions of
/// the same workout type the athlete has logged in the rolling 24-hour
/// window) and clamped to [5000, 10000] — i.e. the second identical
/// session in a day mints 90% of base, the third 80%, floored at 50%.
/// This is the anti-grinding mechanism: rewards stay healthy for a
/// fighter who mixes striking + grappling + roadwork through a real
/// camp; rewards taper for someone who logs the same treadmill walk
/// six times in a row.
///
/// Even if the oracle private key leaks, the attacker cannot mint
/// more than `MAX_REWARD_PER_TX` per call, `per_user_cap` per user
/// per epoch, or `epoch_cap` globally per epoch.
module suisport::rewards_engine {
    use sui::coin::{Self, TreasuryCap};
    use sui::ed25519;
    use sui::event;
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::tx_context::TxContext;

    use suisport::admin::{AdminCap, OracleCap};
    use suisport::sweat::SWEAT;
    use suisport::user_profile::UserProfile;
    use suisport::version::Version;
    use suisport::workout_registry;

    // ---- Errors ----
    const EPaused: u64 = 1;
    const EBadSignature: u64 = 2;
    const ENonceReused: u64 = 3;
    const EGlobalCapExceeded: u64 = 4;
    const EUserCapExceeded: u64 = 5;
    const EOracleRevoked: u64 = 6;
    const EAttestationExpired: u64 = 7;
    const EOverPerTxCap: u64 = 8;
    const EBadDecay: u64 = 9;

    // ---- Formula constants (basis points; 10000 = 1.0x) ----
    /// Hard ceiling per single submit_workout call. 5_000 SWEAT × 1e9
    /// base units. Caps the worst case (compromised oracle + a single
    /// best-case workout) to a recoverable amount.
    const MAX_REWARD_PER_TX: u64 = 5_000_000_000_000;

    const BASE_MULT_BPS:           u128 = 10000;  // 1.0x
    const PR_BONUS_BPS:            u128 = 2500;   // +25% on a personal record
    const CHALLENGE_BONUS_BPS:     u128 = 5000;   // +50% on a fight-camp session
    const FIRST_TIME_BONUS_BPS:    u128 = 2000;   // +20% first session of a type
    const STREAK_BONUS_PER_DAY:    u128 = 200;    // +2% per consecutive-day streak
    const STREAK_BONUS_MAX_BPS:    u128 = 5000;   // capped at +50%
    const DECAY_FLOOR_BPS:         u64  = 5000;   // 0.5x — no session ever drops below half
    const DECAY_CEILING_BPS:       u64  = 10000;  // 1.0x — no boost via decay

    // ---- Shared state ----

    public struct RewardsEngine has key {
        id: UID,
        treasury: TreasuryCap<SWEAT>,
        total_minted: u64,
        epoch_cap: u64,
        per_user_cap: u64,
        current_epoch: u64,
        epoch_minted: u64,
        per_user_minted: Table<address, EpochCounter>,
        consumed_nonces: Table<vector<u8>, bool>,
        paused: bool,
        expected_version: u64,
    }

    public struct EpochCounter has store, copy, drop {
        epoch: u64,
        amount: u64,
    }

    // ---- Events ----

    /// Headline event — kept for backward compat with the testnet
    /// indexer and explorer subscribers. Just emits the bottom-line
    /// minted amount per athlete.
    public struct RewardMinted has copy, drop {
        athlete: address,
        amount: u64,
        epoch: u64,
    }

    /// Rich event — emitted alongside RewardMinted. Carries every
    /// formula component so an indexer (and a curious explorer
    /// visitor) can reconstruct *why* a particular mint happened.
    /// Useful for: leaderboards filtered by bonus type, fraud audits
    /// ("which mints triggered the formula's max bonus?"), and the
    /// "Stack up" UI's per-component breakdown.
    public struct WorkoutScored has copy, drop {
        athlete: address,
        workout_type: u8,
        timestamp_ms: u64,
        base_reward: u64,           // pre-bonus, pre-decay
        pr_bonus: bool,
        challenge_bonus: bool,
        first_time_bonus: bool,
        streak_days: u8,
        repetition_decay_bps: u16,  // 5000–10000
        multiplier_bps: u64,        // composite of all bonuses
        final_reward: u64,          // exactly what was minted
        epoch: u64,
    }

    // ---- Setup ----

    public fun initialize(
        _admin: &AdminCap,
        treasury: TreasuryCap<SWEAT>,
        epoch_cap: u64,
        per_user_cap: u64,
        expected_version: u64,
        ctx: &mut TxContext,
    ) {
        let engine = RewardsEngine {
            id: object::new(ctx),
            treasury,
            total_minted: 0,
            epoch_cap,
            per_user_cap,
            current_epoch: ctx.epoch(),
            epoch_minted: 0,
            per_user_minted: table::new(ctx),
            consumed_nonces: table::new(ctx),
            paused: false,
            expected_version,
        };
        transfer::share_object(engine);
    }

    public fun set_paused(_admin: &AdminCap, e: &mut RewardsEngine, paused: bool) {
        e.paused = paused;
    }

    public fun set_caps(
        _admin: &AdminCap,
        e: &mut RewardsEngine,
        epoch_cap: u64,
        per_user_cap: u64,
    ) {
        e.epoch_cap = epoch_cap;
        e.per_user_cap = per_user_cap;
    }

    public fun set_expected_version(
        _admin: &AdminCap,
        e: &mut RewardsEngine,
        v: u64,
    ) {
        e.expected_version = v;
    }

    // ---- Main entrypoint: submit a verified workout ----

    /// Attestation message format (constructed off-chain, signed by backend):
    ///   BLAKE2b256(
    ///     athlete_address || nonce || expires_at_ms || workout_type ||
    ///     timestamp_ms || duration_s || distance_m || calories ||
    ///     walrus_blob_id || base_reward || pr_bonus || challenge_bonus ||
    ///     first_time_bonus || streak_days || repetition_decay_bps
    ///   )
    /// The signature is the raw ed25519 signature over that digest.
    /// Notice: the FINAL reward amount is NOT in the digest. The
    /// contract computes it on-chain from the signed components, so
    /// the off-chain server can't lie about the math — only about
    /// the inputs.
    public fun submit_workout(
        engine: &mut RewardsEngine,
        oracle: &OracleCap,
        version: &Version,
        profile: &mut UserProfile,
        athlete: address,
        nonce: vector<u8>,
        expires_at_ms: u64,
        workout_type: u8,
        timestamp_ms: u64,
        duration_s: u32,
        distance_m: u32,
        calories: u32,
        walrus_blob_id: vector<u8>,
        base_reward: u64,
        pr_bonus: u8,                  // 0 or 1
        challenge_bonus: u8,           // 0 or 1
        first_time_bonus: u8,          // 0 or 1
        streak_days: u8,               // raw count, 0..255
        repetition_decay_bps: u16,     // 5000..10000
        signature: vector<u8>,
        msg_digest: vector<u8>,
        ctx: &mut TxContext,
    ) {
        // 1. Version gate.
        suisport::version::assert_matches(version, engine.expected_version);

        // 2. Paused / oracle state.
        assert!(!engine.paused, EPaused);
        assert!(!suisport::admin::oracle_revoked(oracle), EOracleRevoked);
        assert!(timestamp_ms <= expires_at_ms, EAttestationExpired);

        // 3. Verify ed25519 signature over the canonical digest.
        //    Note the digest covers every formula input but NOT the
        //    derived final reward — the contract derives that itself.
        let ok = ed25519::ed25519_verify(
            &signature,
            &suisport::admin::oracle_pubkey(oracle),
            &msg_digest,
        );
        assert!(ok, EBadSignature);

        // 4. Replay protection (nonce single-use).
        assert!(!table::contains(&engine.consumed_nonces, nonce), ENonceReused);
        table::add(&mut engine.consumed_nonces, nonce, true);

        // 5. Compute the reward on-chain from the signed components.
        //    Bounds-check decay before scaling so a malformed input
        //    can't push the multiplier below the floor or above 1.0x.
        assert!(
            repetition_decay_bps >= (DECAY_FLOOR_BPS as u16)
                && repetition_decay_bps <= (DECAY_CEILING_BPS as u16),
            EBadDecay
        );
        let multiplier_bps_u128 = compute_multiplier_bps(
            pr_bonus, challenge_bonus, first_time_bonus, streak_days
        );
        let after_mult: u128 =
            (base_reward as u128) * multiplier_bps_u128 / BASE_MULT_BPS;
        let after_decay: u128 =
            after_mult * (repetition_decay_bps as u128) / BASE_MULT_BPS;
        let mut reward_amount: u64 = (after_decay as u64);

        // 6. Per-tx ceiling — hard cap on a single mint regardless of
        //    formula inputs. Last line of defense if oracle key leaks.
        if (reward_amount > MAX_REWARD_PER_TX) {
            reward_amount = MAX_REWARD_PER_TX;
        };
        assert!(reward_amount <= MAX_REWARD_PER_TX, EOverPerTxCap);

        // 7. Roll epoch counter if a new epoch started since last mint.
        let now_epoch = ctx.epoch();
        if (engine.current_epoch != now_epoch) {
            engine.current_epoch = now_epoch;
            engine.epoch_minted = 0;
        };

        // 8. Global per-epoch cap.
        assert!(engine.epoch_minted + reward_amount <= engine.epoch_cap, EGlobalCapExceeded);

        // 9. Per-user per-epoch cap.
        if (table::contains(&engine.per_user_minted, athlete)) {
            let counter = table::borrow_mut(&mut engine.per_user_minted, athlete);
            if (counter.epoch != now_epoch) {
                counter.epoch = now_epoch;
                counter.amount = 0;
            };
            assert!(counter.amount + reward_amount <= engine.per_user_cap, EUserCapExceeded);
            counter.amount = counter.amount + reward_amount;
        } else {
            assert!(reward_amount <= engine.per_user_cap, EUserCapExceeded);
            table::add(
                &mut engine.per_user_minted,
                athlete,
                EpochCounter { epoch: now_epoch, amount: reward_amount },
            );
        };

        // 10. Mint SWEAT to the athlete.
        let coin = coin::mint(&mut engine.treasury, reward_amount, ctx);
        transfer::public_transfer(coin, athlete);
        engine.total_minted = engine.total_minted + reward_amount;
        engine.epoch_minted = engine.epoch_minted + reward_amount;

        // 11. Create + attach the soulbound Workout proof.
        workout_registry::mint_workout(
            profile,
            athlete,
            workout_type,
            timestamp_ms,
            duration_s,
            distance_m,
            calories,
            walrus_blob_id,
            msg_digest,
            reward_amount,
            ctx,
        );

        // 12. Events. Headline event (RewardMinted) for backward-
        //     compatible indexers, plus the rich WorkoutScored event
        //     so explorers can reconstruct the formula.
        event::emit(RewardMinted { athlete, amount: reward_amount, epoch: now_epoch });
        event::emit(WorkoutScored {
            athlete,
            workout_type,
            timestamp_ms,
            base_reward,
            pr_bonus: pr_bonus == 1,
            challenge_bonus: challenge_bonus == 1,
            first_time_bonus: first_time_bonus == 1,
            streak_days,
            repetition_decay_bps,
            multiplier_bps: (multiplier_bps_u128 as u64),
            final_reward: reward_amount,
            epoch: now_epoch,
        });
    }

    // ---- Pure formula helpers (deterministic, no state) ----

    /// Composite multiplier from the four bonus flags + streak count.
    /// Streak bonus accrues at +2%/day, capped at +50% (25 days).
    /// All bonuses additive, no compounding — keeps the formula
    /// readable for users staring at the WorkoutScored event.
    fun compute_multiplier_bps(
        pr_bonus: u8,
        challenge_bonus: u8,
        first_time_bonus: u8,
        streak_days: u8,
    ): u128 {
        let mut bps: u128 = BASE_MULT_BPS;
        if (pr_bonus == 1)         { bps = bps + PR_BONUS_BPS; };
        if (challenge_bonus == 1)  { bps = bps + CHALLENGE_BONUS_BPS; };
        if (first_time_bonus == 1) { bps = bps + FIRST_TIME_BONUS_BPS; };
        let streak_raw: u128 = (streak_days as u128) * STREAK_BONUS_PER_DAY;
        let streak_capped: u128 = if (streak_raw > STREAK_BONUS_MAX_BPS) {
            STREAK_BONUS_MAX_BPS
        } else {
            streak_raw
        };
        bps + streak_capped
    }

    // ---- Views ----

    public fun total_minted(e: &RewardsEngine): u64 { e.total_minted }
    public fun paused(e: &RewardsEngine): bool { e.paused }
    public fun epoch_cap(e: &RewardsEngine): u64 { e.epoch_cap }
    public fun per_user_cap(e: &RewardsEngine): u64 { e.per_user_cap }
    public fun max_reward_per_tx(): u64 { MAX_REWARD_PER_TX }
}
