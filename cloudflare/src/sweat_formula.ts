// SWEAT reward formula — server-side mirror of the on-chain formula
// in `move/suisport/sources/rewards_engine.move`.
//
// The on-chain `submit_workout` recomputes the final reward from the
// signed formula components, so this file's only job is to:
//   1. Decide every component (PR? challenge? streak? decay?) from
//      the user's history in D1.
//   2. Return the values that get fed into the oracle digest +
//      submit_workout call.
// The MOVE contract owns the math. Keep this file's BPS constants in
// lockstep with the constants in rewards_engine.move — divergence
// means the contract recomputes a different number than this file
// expected and the indexer's WorkoutScored event won't match the
// minted amount.
//
// Formula recap (basis points; 10000 = 1.0x):
//
//   multiplier = 10000
//              + 2500  if pr_bonus
//              + 5000  if challenge_bonus
//              + 2000  if first_time_bonus
//              + min(streak_days * 200, 5000)
//
//   reward = base * multiplier / 10000 * decay / 10000
//   reward = min(reward, MAX_REWARD_PER_TX)
//
// `decay` is clamped to [5000, 10000] so the second identical session
// in a 24-hour window mints 90% of base, the third 80%, floored at
// 50%. Encourages variety; punishes grinding the treadmill at 1pm.

import type { Env } from "./env.js";

// ---- Constants — keep in lockstep with rewards_engine.move ----

export const BASE_MULT_BPS         = 10_000n;
export const PR_BONUS_BPS          = 2_500n;
export const CHALLENGE_BONUS_BPS   = 5_000n;
export const FIRST_TIME_BONUS_BPS  = 2_000n;
export const STREAK_BONUS_PER_DAY  = 200n;
export const STREAK_BONUS_MAX_BPS  = 5_000n;
export const DECAY_FLOOR_BPS       = 5_000n;
export const DECAY_CEILING_BPS     = 10_000n;
/// 5_000 SWEAT × 1e9 base units. Hard ceiling per single submission.
export const MAX_REWARD_PER_TX     = 5_000_000_000_000n;

/// SWEAT has 9 decimals — one Sweat Point = one base SWEAT unit.
export const SWEAT_DECIMALS = 1_000_000_000n;

// ---- Component decision functions ----

export interface FormulaComponents {
    /// Pre-bonus, pre-decay reward in base SWEAT units. Source: server-
    /// side recompute from canonical workout payload (NEVER trust
    /// `body.points` from the client).
    baseReward: bigint;
    prBonus: 0 | 1;
    challengeBonus: 0 | 1;
    firstTimeBonus: 0 | 1;
    streakDays: number;          // 0..255, raw count (capped on chain)
    repetitionDecayBps: number;  // 5000..10000
}

export interface FormulaInputs {
    baseSweatPoints: number;     // off-chain Sweat Points value (pre-decimals)
    workoutType: string;
    athleteId: string;
    /// True when the workout's pace beats the athlete's existing PR
    /// for any tracked distance (1k, 5k, 10k, half, full).
    isPersonalRecord: boolean;
    /// True when the workout counts toward an active joined challenge.
    isChallengeContribution: boolean;
}

/// Build the component bundle from D1 lookups + the inputs the
/// server already knows. Pure; no side effects on D1.
export async function deriveFormulaComponents(
    env: Env,
    inputs: FormulaInputs
): Promise<FormulaComponents> {
    // Base reward — the off-chain Sweat Points scaled to 9-decimal
    // base units. SweatPoints.forWorkout in iOS computes this; the
    // server mirrors via fraud.vetWorkout.maxPointsByMinute. Source
    // of truth on chain is whatever we sign + submit.
    const baseReward = BigInt(Math.max(0, inputs.baseSweatPoints))
        * SWEAT_DECIMALS;

    // First-time bonus — has the athlete ever logged this workout
    // type before? If not, +20%. Encourages exploration of the
    // martial-arts pillars.
    const prevCount = await env.DB.prepare(
        `SELECT COUNT(*) AS n
         FROM workouts
         WHERE athlete_id = ? AND type = ? AND verified = 1`
    ).bind(inputs.athleteId, inputs.workoutType).first<{ n: number }>();
    const firstTimeBonus: 0 | 1 = (prevCount?.n ?? 0) === 0 ? 1 : 0;

    // Streak — pull the existing streaks row. iOS pushes streak
    // updates after every workout submit so this is fresh.
    const streakRow = await env.DB.prepare(
        `SELECT current_days FROM streaks WHERE athlete_id = ?`
    ).bind(inputs.athleteId).first<{ current_days: number }>();
    const streakDays = Math.max(0, Math.min(255, streakRow?.current_days ?? 0));

    // Repetition decay — count workouts of the same type the athlete
    // logged in the last 24 hours. Each prior session knocks 1000 bps
    // (10%) off, floored at 5000 bps (50%). First session of the day
    // is full strength.
    const repsRow = await env.DB.prepare(
        `SELECT COUNT(*) AS n
         FROM workouts
         WHERE athlete_id = ? AND type = ?
           AND start_date > unixepoch() - 86400`
    ).bind(inputs.athleteId, inputs.workoutType).first<{ n: number }>();
    const priorReps = repsRow?.n ?? 0;
    const decayRaw = Number(BASE_MULT_BPS) - priorReps * 1000;
    const repetitionDecayBps = Math.max(
        Number(DECAY_FLOOR_BPS),
        Math.min(Number(DECAY_CEILING_BPS), decayRaw)
    );

    return {
        baseReward,
        prBonus: inputs.isPersonalRecord ? 1 : 0,
        challengeBonus: inputs.isChallengeContribution ? 1 : 0,
        firstTimeBonus,
        streakDays,
        repetitionDecayBps,
    };
}

// ---- The math itself ----

/// Compute the final SWEAT mint amount from the components. Mirror of
/// `compute_multiplier_bps` + the inline math in
/// rewards_engine::submit_workout. We keep the server-side copy in
/// sync so the indexer's `WorkoutScored` event always lines up with
/// what the contract minted (a divergence here = an audit alert).
export function computeFinalReward(c: FormulaComponents): bigint {
    let multBps: bigint = BASE_MULT_BPS;
    if (c.prBonus === 1)         multBps += PR_BONUS_BPS;
    if (c.challengeBonus === 1)  multBps += CHALLENGE_BONUS_BPS;
    if (c.firstTimeBonus === 1)  multBps += FIRST_TIME_BONUS_BPS;
    const streakRaw = BigInt(c.streakDays) * STREAK_BONUS_PER_DAY;
    const streakCap = streakRaw > STREAK_BONUS_MAX_BPS
        ? STREAK_BONUS_MAX_BPS
        : streakRaw;
    multBps += streakCap;

    const decay = BigInt(
        Math.max(
            Number(DECAY_FLOOR_BPS),
            Math.min(Number(DECAY_CEILING_BPS), c.repetitionDecayBps)
        )
    );

    const afterMult = (c.baseReward * multBps) / BASE_MULT_BPS;
    const afterDecay = (afterMult * decay) / BASE_MULT_BPS;
    return afterDecay > MAX_REWARD_PER_TX ? MAX_REWARD_PER_TX : afterDecay;
}

/// Convenient explainer string for logs / admin dashboard.
export function describeReward(c: FormulaComponents, final: bigint): string {
    const parts = [
        `base=${c.baseReward}`,
        c.prBonus === 1 && "+PR",
        c.challengeBonus === 1 && "+CHALLENGE",
        c.firstTimeBonus === 1 && "+FIRST_TIME",
        c.streakDays > 0 && `+STREAK(${c.streakDays}d)`,
        c.repetitionDecayBps < 10000
            && `decay=${(c.repetitionDecayBps / 100).toFixed(0)}%`,
    ].filter(Boolean).join(" ");
    return `${parts} → ${final}`;
}
