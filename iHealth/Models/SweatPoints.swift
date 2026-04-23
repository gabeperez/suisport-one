import Foundation

/// User-facing currency. We NEVER show "$SWEAT" in the main app —
/// that conversion lives in a separate external flow per App Store rules.
struct SweatPoints: Equatable {
    var total: Int
    var weekly: Int
    var streakDays: Int

    static let zero = SweatPoints(total: 0, weekly: 0, streakDays: 0)

    /// Points formula. Conservative and explainable.
    /// - Distance-based sports: 60 pts/km + 2 pts/active-minute
    /// - Non-distance sports: 6 pts/active-minute
    /// - Manually-entered workouts are capped at 30% of calculated value
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
        }
        let adjusted = w.isUserEntered ? base * 0.3 : base
        return max(0, Int(adjusted.rounded()))
    }
}
