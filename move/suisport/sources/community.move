/// Fighter community memberships. A fan unlocks a fighter's
/// gated community by paying SWEAT — the SWEAT goes to the fighter
/// as direct revenue share, and the fan gets a soulbound
/// `CommunityPass` NFT that proves membership.
///
/// Why revenue share instead of a treasury burn:
///   • Compelling on-chain story — fans literally pay fighters in
///     SWEAT, visible as a coin transfer on Suiscan.
///   • No TreasuryCap juggling — the existing `RewardsEngine`
///     module stays untouched.
///   • Mirrors how Patreon / Weverse / OnlyFans actually work:
///     fans → creators, with the platform skimming nothing on
///     this primitive.
///
/// The pass is soulbound: `key` only, no `store`, no
/// `public_transfer`. Membership can't be sold or transferred
/// after it lands in the fan's wallet.
module suisport::community {
    // `transfer`, `TxContext`, and `option` are auto-imported in
    // Sui Move 2024 — listing them explicitly produces duplicate-
    // alias warnings, so we leave them implicit.
    use sui::coin::{Self, Coin};
    use sui::event;

    use suisport::sweat::SWEAT;
    use suisport::user_profile::{Self, UserProfile};
    use suisport::version::{Self, Version};

    /// Pinned package version. Bumped via `version::bump` when this
    /// module's entry surface changes.
    const EXPECTED_VERSION: u64 = 1;

    // ---- Errors ----

    const E_PAYMENT_TOO_LOW: u64 = 2;

    // ---- Object ----

    /// Soulbound proof-of-membership for a fighter's community.
    /// Carries the receipt fields a curious explorer visitor would
    /// want — handle, fighter address, paid amount, timestamp.
    public struct CommunityPass has key {
        id: UID,
        /// Fan address that holds the pass (always equals the tx
        /// sender, since the pass is soulbound on creation).
        member: address,
        /// Stable handle of the fighter whose community was unlocked.
        fighter_handle: vector<u8>,
        /// Sui address that received the SWEAT revenue. Stored on
        /// the pass so the receipt is self-contained.
        fighter_address: address,
        /// Amount of SWEAT (in mist, 1e-9) the fan paid.
        sweat_paid: u64,
        /// Unix milliseconds when the unlock landed on chain.
        unlocked_at_ms: u64,
        /// Per-member monotonic sequence number from UserProfile.
        seq: u64,
    }

    // ---- Events ----

    public struct CommunityUnlocked has copy, drop {
        member: address,
        seq: u64,
        pass_id: ID,
        fighter_handle: vector<u8>,
        fighter_address: address,
        sweat_paid: u64,
        unlocked_at_ms: u64,
    }

    // ---- Entry ----

    /// Unlock a fighter's community. Caller hands in a `Coin<SWEAT>`,
    /// which is forwarded to `fighter_address` as revenue share, and
    /// receives a soulbound `CommunityPass` in return.
    ///
    /// `min_sweat` is the gate — the pass mints only if the coin's
    /// value meets or exceeds it. Setting it via the call lets the
    /// off-chain catalog adjust per-fighter pricing without a
    /// contract upgrade.
    public fun unlock_community(
        version_obj: &Version,
        profile: &mut UserProfile,
        payment: Coin<SWEAT>,
        fighter_handle: vector<u8>,
        fighter_address: address,
        min_sweat: u64,
        unlocked_at_ms: u64,
        ctx: &mut TxContext,
    ) {
        version::assert_matches(version_obj, EXPECTED_VERSION);

        let value = coin::value(&payment);
        assert!(value >= min_sweat, E_PAYMENT_TOO_LOW);

        let member = ctx.sender();
        let seq = user_profile::total_workouts(profile) + 1;

        let pass = CommunityPass {
            id: object::new(ctx),
            member,
            fighter_handle,
            fighter_address,
            sweat_paid: value,
            unlocked_at_ms,
            seq,
        };
        let pass_id = object::id(&pass);

        event::emit(CommunityUnlocked {
            member,
            seq,
            pass_id,
            fighter_handle,
            fighter_address,
            sweat_paid: value,
            unlocked_at_ms,
        });

        // Forward the SWEAT to the fighter — this is the visible
        // revenue-share transfer on Suiscan. `public_transfer` is
        // legal because `Coin<SWEAT>` has `store`.
        transfer::public_transfer(payment, fighter_address);

        // Soulbound transfer of the pass to the fan.
        transfer::transfer(pass, member);
    }

    // ---- Read accessors ----

    public fun member(p: &CommunityPass): address { p.member }
    public fun fighter_handle(p: &CommunityPass): vector<u8> { p.fighter_handle }
    public fun fighter_address(p: &CommunityPass): address { p.fighter_address }
    public fun sweat_paid(p: &CommunityPass): u64 { p.sweat_paid }
    public fun unlocked_at_ms(p: &CommunityPass): u64 { p.unlocked_at_ms }
    public fun seq(p: &CommunityPass): u64 { p.seq }
}
