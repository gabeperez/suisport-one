/// Per-user profile. Owned by the user's address. Workouts attach as dynamic
/// object fields so the profile can carry an arbitrarily-long history without
/// paying storage cost up-front for unused slots.
module suisport::user_profile {
    use sui::dynamic_object_field as dof;
    use sui::event;
    use sui::transfer;
    use sui::tx_context::TxContext;

    public struct UserProfile has key {
        id: UID,
        owner: address,
        total_workouts: u64,
        total_distance_m: u64,
        total_duration_s: u64,
        lifetime_sweat: u64,
        streak_days: u32,
        last_workout_ts_ms: u64,
    }

    public struct ProfileCreated has copy, drop { owner: address, profile_id: ID }

    /// Create a new profile and transfer it to the caller.
    public fun create(ctx: &mut TxContext): UserProfile {
        let owner = ctx.sender();
        let p = UserProfile {
            id: object::new(ctx),
            owner,
            total_workouts: 0,
            total_distance_m: 0,
            total_duration_s: 0,
            lifetime_sweat: 0,
            streak_days: 0,
            last_workout_ts_ms: 0,
        };
        event::emit(ProfileCreated { owner, profile_id: object::id(&p) });
        p
    }

    /// Entry-style create for use in a PTB.
    public fun create_and_transfer(ctx: &mut TxContext) {
        let p = create(ctx);
        let to = p.owner;
        transfer::transfer(p, to);
    }

    // --- Field access ---

    public fun owner(p: &UserProfile): address { p.owner }
    public fun total_workouts(p: &UserProfile): u64 { p.total_workouts }
    public fun lifetime_sweat(p: &UserProfile): u64 { p.lifetime_sweat }

    // --- Package-internal mutators (only workout_registry calls these) ---

    public(package) fun record_workout(
        p: &mut UserProfile,
        duration_s: u32,
        distance_m: u32,
        sweat_minted: u64,
        ts_ms: u64,
    ) {
        p.total_workouts = p.total_workouts + 1;
        p.total_duration_s = p.total_duration_s + (duration_s as u64);
        p.total_distance_m = p.total_distance_m + (distance_m as u64);
        p.lifetime_sweat = p.lifetime_sweat + sweat_minted;
        // Streak is computed off-chain and passed in via admin snapshot in practice.
        p.last_workout_ts_ms = ts_ms;
    }

    public(package) fun attach_workout<T: key + store>(
        p: &mut UserProfile,
        seq: u64,
        workout: T,
    ) {
        dof::add(&mut p.id, seq, workout);
    }

    public(package) fun id_mut(p: &mut UserProfile): &mut UID { &mut p.id }
}
