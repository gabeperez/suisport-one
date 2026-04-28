/// Camp completion records. A `CampCompleted` is minted when an athlete
/// finishes every session of a fighter's structured training plan
/// (e.g. "Yuya's Tribe Tokyo Camp", "Takeru's Fight Camp").
///
/// Soulbound by design — `key` only, no `store` — so the certificate
/// can never be transferred or sold after it lands in the athlete's
/// wallet. Same pattern as `workout_registry::Workout`.
///
/// Phase 2 entry point: the server calls `mint_camp_completion` after
/// confirming every session in a plan has been recorded on chain.
/// Authority gate is the same `OracleCap` that controls `submit_workout`,
/// so only the operator-oracle keypair can mint.
module suisport::camp_registry {
    // `transfer`, `TxContext`, and `option` are auto-imported in
    // Sui Move 2024 — listing them explicitly produces duplicate-
    // alias warnings, so we leave them implicit.
    use sui::event;

    use suisport::user_profile::{Self, UserProfile};
    use suisport::admin::OracleCap;
    use suisport::version::{Self, Version};

    /// Pinned package version. Bumped via `version::bump` when this
    /// module's entry surface changes — keeps stale clients from
    /// hitting an upgraded contract with the old call shape.
    const EXPECTED_VERSION: u64 = 1;

    // ---- Object ----

    /// Soulbound certificate of camp completion. `key` only — no
    /// `store`, so `public_transfer` is disallowed once it lands in
    /// the athlete's wallet.
    public struct CampCompleted has key {
        id: UID,
        /// Wallet that completed the camp.
        athlete: address,
        /// Stable handle of the fighter whose camp this is — e.g.
        /// "k1takeru", "yuya_wakamatsu", "nadaka". Carried as bytes
        /// so off-chain indexers can render the matching avatar +
        /// metadata without a separate registry lookup.
        fighter_handle: vector<u8>,
        /// Stable identifier for the specific plan template (e.g.
        /// "fight_camp_v1"). Lets a single fighter publish multiple
        /// camps over time without colliding.
        plan_id: vector<u8>,
        /// Number of sessions completed (always equals the camp's
        /// total — the entry function only fires on full completion).
        sessions_completed: u32,
        /// Unix milliseconds when the final session landed on chain.
        completed_at_ms: u64,
        /// Per-athlete monotonic sequence number from UserProfile.
        seq: u64,
    }

    // ---- Events ----

    public struct CampCompletedEvent has copy, drop {
        athlete: address,
        seq: u64,
        camp_id: ID,
        fighter_handle: vector<u8>,
        plan_id: vector<u8>,
        sessions_completed: u32,
        completed_at_ms: u64,
    }

    // ---- Entry ----

    /// Mint a soulbound camp-completion certificate. Gated on
    /// `OracleCap` so only the server's oracle keypair can call —
    /// keeps clients from forging completions.
    public fun mint_camp_completion(
        _oracle: &OracleCap,
        version_obj: &Version,
        profile: &mut UserProfile,
        athlete: address,
        fighter_handle: vector<u8>,
        plan_id: vector<u8>,
        sessions_completed: u32,
        completed_at_ms: u64,
        ctx: &mut TxContext,
    ) {
        // Same version-pinning pattern `rewards_engine` uses — when
        // the package is upgraded, admin bumps the global Version
        // and this entry function stops accepting txs from old code.
        version::assert_matches(version_obj, EXPECTED_VERSION);

        let seq = user_profile::total_workouts(profile) + 1;
        let cert = CampCompleted {
            id: object::new(ctx),
            athlete,
            fighter_handle,
            plan_id,
            sessions_completed,
            completed_at_ms,
            seq,
        };
        let camp_id = object::id(&cert);

        event::emit(CampCompletedEvent {
            athlete,
            seq,
            camp_id,
            fighter_handle,
            plan_id,
            sessions_completed,
            completed_at_ms,
        });

        // Soulbound transfer — `key`-only means only this module's
        // direct transfer is possible, and we never call it again.
        transfer::transfer(cert, athlete);
    }

    // ---- Read accessors ----

    public fun athlete(c: &CampCompleted): address { c.athlete }
    public fun fighter_handle(c: &CampCompleted): vector<u8> { c.fighter_handle }
    public fun plan_id(c: &CampCompleted): vector<u8> { c.plan_id }
    public fun sessions_completed(c: &CampCompleted): u32 { c.sessions_completed }
    public fun completed_at_ms(c: &CampCompleted): u64 { c.completed_at_ms }
    public fun seq(c: &CampCompleted): u64 { c.seq }
}
