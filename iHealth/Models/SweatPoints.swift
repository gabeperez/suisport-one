import Foundation

/// User-facing currency. We NEVER show "$SWEAT" in the main app —
/// that conversion lives in a separate external flow per App Store rules.
struct SweatPoints: Equatable {
    var total: Int
    var weekly: Int
    var streakDays: Int

    static let zero = SweatPoints(total: 0, weekly: 0, streakDays: 0)

    /// Points formula. Conservative and explainable.
    /// - Distance sports: 60 pts/km + 2 pts/active-minute
    /// - Swim: higher per-km rate because distance scales differently
    /// - Fight-camp workouts: rates tuned to real session intensity —
    ///   MMA sparring is the hardest, striking + grappling are even,
    ///   conditioning is moderate with a distance bonus when logged
    ///   with a route, recovery awards a small completion reward so
    ///   fighters aren't punished for doing the right thing.
    /// - Generic gym workouts: flat 6 pts/minute
    /// - Manually-entered workouts are capped at 30% of calculated
    ///   value (App Attest signatures from Apple Watch are the
    ///   trusted path; manual log is backstop only)
    static func forWorkout(_ w: Workout) -> Int {
        let minutes = w.duration / 60.0
        let base: Double
        switch w.type {
        case .run, .walk, .ride, .hike:
            let km = (w.distanceMeters ?? 0) / 1000.0
            base = km * 60 + minutes * 2
        case .swim:
            let km = (w.distanceMeters ?? 0) / 1000.0
            base = km * 300 + minutes * 4
        case .lift, .yoga, .hiit, .other:
            base = minutes * 6
        // Fight camp — rates reflect session intensity, not distance.
        case .mma:
            // Full sparring / situational rounds. Highest per-minute
            // rate in the app.
            base = minutes * 10
        case .striking, .grappling:
            // Bag work, pad rounds, BJJ rolls, clinch drills. Still
            // intense but slightly below live MMA sparring.
            base = minutes * 8
        case .conditioning:
            // Fighter cardio — circuits, sport-specific engine work.
            // Distance bonus when the session is logged with a route
            // (roadwork treadmill intervals, etc.).
            let km = (w.distanceMeters ?? 0) / 1000.0
            base = km * 40 + minutes * 6
        case .recovery:
            // Mobility, sauna, stretching. Low point reward but
            // non-zero so fighters can build a streak without
            // hammering themselves every day of a camp.
            base = minutes * 3
        }
        let adjusted = w.isUserEntered ? base * 0.3 : base
        return max(0, Int(adjusted.rounded()))
    }
}
