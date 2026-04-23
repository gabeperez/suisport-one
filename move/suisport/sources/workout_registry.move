/// Workout records. Soulbound by design: `Workout` has `key` but not `store`,
/// so it can only move via the `transfer::transfer` call inside this module,
/// and only at creation. After that it's locked to the athlete forever.
///
/// Bulk data (GPS trace, HR stream, photos) lives in Walrus — we just carry
/// the blob id + the attestation hash on-chain.
module suisport::workout_registry {
    use sui::event;
    use sui::transfer;
    use sui::tx_context::TxContext;

    use suisport::user_profile::{Self, UserProfile};

    /// Soulbound: `key` only. No `store`, so `public_transfer` is disallowed.
    public struct Workout has key {
        id: UID,
        athlete: address,
        workout_type: u8,
        timestamp_ms: u64,
        duration_s: u32,
        distance_m: u32,
        calories: u32,
        walrus_blob_id: vector<u8>,
        attestation_hash: vector<u8>,
        reward_amount: u64,
        seq: u64,
    }

    public struct WorkoutSubmitted has copy, drop {
        athlete: address,
        seq: u64,
        workout_id: ID,
        workout_type: u8,
        distance_m: u32,
        duration_s: u32,
        reward_amount: u64,
        timestamp_ms: u64,
    }

    /// Package-internal constructor. Called by `rewards_engine::submit_workout`
    /// after all attestation, replay, and rate-limit checks have passed.
    public(package) fun mint_workout(
        profile: &mut UserProfile,
        athlete: address,
        workout_type: u8,
        timestamp_ms: u64,
        duration_s: u32,
        distance_m: u32,
        calories: u32,
        walrus_blob_id: vector<u8>,
        attestation_hash: vector<u8>,
        reward_amount: u64,
        ctx: &mut TxContext,
    ) {
        let seq = user_profile::total_workouts(profile) + 1;
        let workout = Workout {
            id: object::new(ctx),
            athlete,
            workout_type,
            timestamp_ms,
            duration_s,
            distance_m,
            calories,
            walrus_blob_id,
            attestation_hash,
            reward_amount,
            seq,
        };
        let workout_id = object::id(&workout);

        // Update profile counters.
        user_profile::record_workout(
            profile,
            duration_s,
            distance_m,
            reward_amount,
            timestamp_ms,
        );

        event::emit(WorkoutSubmitted {
            athlete,
            seq,
            workout_id,
            workout_type,
            distance_m,
            duration_s,
            reward_amount,
            timestamp_ms,
        });

        // Soulbound transfer — key-only means only this module's transfer is possible.
        transfer::transfer(workout, athlete);
    }

    public fun athlete(w: &Workout): address { w.athlete }
    public fun seq(w: &Workout): u64 { w.seq }
    public fun reward(w: &Workout): u64 { w.reward_amount }
    public fun walrus_blob_id(w: &Workout): vector<u8> { w.walrus_blob_id }
}
