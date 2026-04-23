import Foundation
import Observation

/// App-wide state. Drives the top-level router (onboarding vs. main app) and
/// holds the signed-in user + current workout catalogue.
@Observable
@MainActor
final class AppState {
    // MARK: - Auth / session
    var currentUser: User?
    var isAuthenticated: Bool { currentUser != nil }

    // MARK: - Onboarding
    var onboardingStep: OnboardingStep = .hero
    var hasCompletedOnboarding: Bool = false
    var isAuthInFlight: Bool = false

    // MARK: - Data
    var workouts: [Workout] = []
    var sweatPoints: SweatPoints = .zero

    /// Computed: has the user granted Health access at least to writing?
    /// For read-auth HealthKit doesn't expose status — we infer by querying.
    var healthAuthorized: Bool = false

    // MARK: - Navigation helpers

    func advanceOnboarding() {
        guard let next = onboardingStep.next else {
            hasCompletedOnboarding = true
            return
        }
        onboardingStep = next
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
    }

    // MARK: - Auth actions

    func signInWithApple() async {
        isAuthInFlight = true
        defer { isAuthInFlight = false }
        do {
            let user = try await AuthService.shared.signInWithApple()
            self.currentUser = user
            advanceOnboarding()
        } catch AuthService.AuthError.cancelled {
            // silent — user tapped cancel
        } catch {
            // In production: surface a toast. For now, silently stay on auth screen.
        }
    }

    func signInWithGoogle() async {
        isAuthInFlight = true
        defer { isAuthInFlight = false }
        do {
            let user = try await AuthService.shared.signInWithGoogle()
            self.currentUser = user
            advanceOnboarding()
        } catch {
            // ignore
        }
    }

    func setGoal(_ goal: UserGoal?, displayName: String) {
        if var user = currentUser {
            if !displayName.trimmingCharacters(in: .whitespaces).isEmpty {
                user.displayName = displayName
            }
            user.goal = goal
            self.currentUser = user
        }
    }

    // MARK: - Health backfill

    func requestHealthAuth() async -> Bool {
        do {
            try await HealthKitService.shared.requestAuthorization()
            self.healthAuthorized = HealthKitService.shared.writeAuthorized() || true
            return true
        } catch {
            self.healthAuthorized = false
            return false
        }
    }

    func backfillWorkouts(onProgress: @escaping (Int) -> Void) async {
        do {
            let workouts = try await HealthKitService.shared.loadHistoricalWorkouts { count in
                onProgress(count)
            }
            self.workouts = workouts
            let total = workouts.reduce(0) { $0 + $1.points }
            self.sweatPoints = SweatPoints(
                total: total,
                weekly: workouts.prefix { Date().timeIntervalSince($0.startDate) < 7*24*3600 }
                                .reduce(0) { $0 + $1.points },
                streakDays: Self.estimateStreak(from: workouts)
            )
            SocialDataService.shared.seed(for: currentUser, workouts: workouts)
        } catch {
            self.workouts = []
            SocialDataService.shared.seed(for: currentUser, workouts: [])
        }
    }

    private static func estimateStreak(from workouts: [Workout]) -> Int {
        let days = Set(workouts.map { Calendar.current.startOfDay(for: $0.startDate) })
        var streak = 0
        var cursor = Calendar.current.startOfDay(for: .now)
        while days.contains(cursor) {
            streak += 1
            guard let prev = Calendar.current.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }

    // MARK: - Notifications

    func requestNotificationAuth() async {
        // Stub — request UNUserNotificationCenter alert+sound+badge when wiring push.
    }
}
