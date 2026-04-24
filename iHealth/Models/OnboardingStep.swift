import Foundation

enum OnboardingStep: Int, CaseIterable, Comparable {
    // Order: hero → ageGate (before anything that creates an account or reads
    // Health data — legal requirement) → auth → nameGoal → healthPermission
    // → backfill → notifications.
    case hero = 0
    case ageGate = 1
    case auth = 2
    case nameGoal = 3
    case healthPermission = 4
    case backfill = 5
    case notifications = 6

    static func < (lhs: OnboardingStep, rhs: OnboardingStep) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var next: OnboardingStep? {
        OnboardingStep(rawValue: rawValue + 1)
    }

    /// Whether this step is visually a step in the progress dots (hero is not).
    var showsProgress: Bool { self != .hero }

    /// Number of dots to show in the step indicator.
    static let progressStepCount = 6
    var progressIndex: Int { max(0, rawValue - 1) }
}
