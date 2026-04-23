/// The minting engine.
///
/// Holds the `TreasuryCap<SWEAT>` inside a shared object. Every mint goes
/// through `submit_workout`, which:
///   1. Verifies the package version matches.
///   2. Verifies the ed25519 attestation from the backend oracle.
///   3. Checks the nonce hasn't been consumed.
///   4. Enforces per-epoch global and per-user mint caps.
///   5. Mints SWEAT, creates a soulbound Workout, and attaches it to the user's profile.
///
/// Even if the oracle private key leaks, the attacker cannot mint more than
/// `epoch_cap` per epoch or `per_user_cap` per user per epoch.
module suisport::rewards_engine {
    use sui::coin::{Self, TreasuryCap};
    use sui::ed25519;
    use sui::event;
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::tx_context::TxContext;

    use suisport::admin::{AdminCap, OracleCap};
    use suisport::sweat::SWEAT;
    use suisport::user_profile::{Self, UserProfile};
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
    public struct RewardMinted has copy, drop {
        athlete: address,
        amount: u64,
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
    ///     walrus_blob_id || reward_amount
    ///   )
    /// The signature is the raw ed25519 signature over that digest.
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
        reward_amount: u64,
        signature: vector<u8>,
        msg_digest: vector<u8>,
        ctx: &mut TxContext,
    ) {
        // 1. Version gate
        suisport::version::assert_matches(version, engine.expected_version);

        // 2. Paused / oracle state
        assert!(!engine.paused, EPaused);
        assert!(!suisport::admin::oracle_revoked(oracle), EOracleRevoked);
        assert!(timestamp_ms <= expires_at_ms, EAttestationExpired);

        // 3. Verify ed25519 signature over the canonical digest
        let ok = ed25519::ed25519_verify(
            &signature,
            &suisport::admin::oracle_pubkey(oracle),
            &msg_digest,
        );
        assert!(ok, EBadSignature);

        // 4. Replay protection
        assert!(!table::contains(&engine.consumed_nonces, nonce), ENonceReused);
        table::add(&mut engine.consumed_nonces, nonce, true);

        // 5. Roll epoch if needed
        let now_epoch = ctx.epoch();
        if (engine.current_epoch != now_epoch) {
            engine.current_epoch = now_epoch;
            engine.epoch_minted = 0;
        };

        // 6. Global cap
        assert!(engine.epoch_minted + reward_amount <= engine.epoch_cap, EGlobalCapExceeded);

        // 7. Per-user cap
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

        // 8. Mint SWEAT to the athlete
        let coin = coin::mint(&mut engine.treasury, reward_amount, ctx);
        transfer::public_transfer(coin, athlete);
        engine.total_minted = engine.total_minted + reward_amount;
        engine.epoch_minted = engine.epoch_minted + reward_amount;

        // 9. Create + attach soulbound Workout
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

        event::emit(RewardMinted { athlete, amount: reward_amount, epoch: now_epoch });
    }

    // ---- Views ----

    public fun total_minted(e: &RewardsEngine): u64 { e.total_minted }
    public fun paused(e: &RewardsEngine): bool { e.paused }
    public fun epoch_cap(e: &RewardsEngine): u64 { e.epoch_cap }
}
