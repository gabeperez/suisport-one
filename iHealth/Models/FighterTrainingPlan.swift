import Foundation

/// A fighter's structured training camp — an ordered sequence of
/// training sessions the user works through one at a time. Built to
/// match how real fight camps run: striking, grappling, conditioning,
/// recovery — sequenced, sequential, can't be skipped.
///
/// Completing all sessions auto-unlocks the fighter's community (the
/// "train like them" path from Phase 1 of the community feature).
struct FighterTrainingPlan: Identifiable, Hashable, Codable {
    /// Same as `Athlete.id` — one camp per fighter.
    var id: String
    var title: String
    var subtitle: String
    var sessions: [TrainingSession]
}

/// Single session within a fighter's camp. The `index` defines the
/// fixed sequence — sessions must be completed in order.
struct TrainingSession: Identifiable, Hashable, Codable {
    /// Stable key (e.g. "yuya-1", "takeru-3") so persisted progress
    /// survives a relaunch even though the Identifiable id is a UUID.
    var stableKey: String
    var index: Int
    var title: String
    /// One-line description of the session — drills, focus areas.
    var summary: String
    /// Workout type the session expects. Used to pre-filter matches
    /// when wiring into the live recorder (Phase 2).
    var workoutType: String
    var targetMinutes: Int
    var intensity: Intensity
    /// Numbered, concrete steps the user can follow. Rendered as an
    /// ordered list in SessionLogSheet — Apple-Fitness-style.
    var steps: [String]
    /// Placeholder demo video URL — embedded above the steps so the
    /// user can watch a representative workout while reading along.
    /// Phase 2 swaps these for fighter-specific footage.
    var videoURL: String

    var id: String { stableKey }

    enum Intensity: String, Codable, Hashable {
        case easy, moderate, hard, peak

        var label: String {
            switch self {
            case .easy:     return "Easy"
            case .moderate: return "Moderate"
            case .hard:     return "Hard"
            case .peak:     return "Peak"
            }
        }
    }
}

/// Per-user progress against a single fighter's training plan.
/// Persisted to UserDefaults so progress survives relaunches and
/// device-state changes within the same install.
struct UserTrainingProgress: Codable, Equatable {
    /// `Athlete.id` of the fighter whose camp this is.
    var fighterId: String
    /// Stable keys of sessions the user has marked complete. Stored
    /// as a Set to avoid double-counting; ordered behavior comes
    /// from `currentSessionIndex(in:)`.
    var completedSessionKeys: Set<String>
    var startedAt: Date
    var lastCompletedAt: Date?

    /// Index of the next session the user can work on (lowest index
    /// not yet in `completedSessionKeys`). Returns sessions.count
    /// when the entire camp is finished.
    func currentSessionIndex(in plan: FighterTrainingPlan) -> Int {
        for session in plan.sessions {
            if !completedSessionKeys.contains(session.stableKey) {
                return session.index
            }
        }
        return plan.sessions.count
    }

    /// True when the user has completed every session in the plan.
    func isComplete(in plan: FighterTrainingPlan) -> Bool {
        currentSessionIndex(in: plan) >= plan.sessions.count
    }

    /// 0...1 progress for ProgressView / ring rendering.
    func progressFraction(in plan: FighterTrainingPlan) -> Double {
        guard !plan.sessions.isEmpty else { return 0 }
        let completed = plan.sessions.filter { completedSessionKeys.contains($0.stableKey) }.count
        return Double(completed) / Double(plan.sessions.count)
    }
}
