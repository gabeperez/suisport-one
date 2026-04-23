import Foundation

enum OnboardingStep: Int, CaseIterable, Comparable {
    case hero = 0
    case auth = 1
    case nameGoal = 2
    case healthPermission = 3
    case backfill = 4
    case notifications = 5

    static func < (lhs: OnboardingStep, rhs: OnboardingStep) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var next: OnboardingStep? {
        OnboardingStep(rawValue: rawValue + 1)
    }

    /// Whether this step is visually a step in the progress dots (hero is not).
    var showsProgress: Bool { self != .hero }

    /// Number of dots to show in the step indicator.
    static let progressStepCount = 5
    var progressIndex: Int { max(0, rawValue - 1) }
}
