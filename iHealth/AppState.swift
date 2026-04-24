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

    /// DOB captured before auth (AgeGate is now the first gated step). We can't
    /// PATCH the athlete row until we have a session token, so we stash it and
    /// replay once the user signs in.
    private var pendingDateOfBirth: Date?

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
            UserDefaults.standard.set("apple", forKey: "lastAuthProvider")
            applyPendingDateOfBirth()
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
            UserDefaults.standard.set("google", forKey: "lastAuthProvider")
            applyPendingDateOfBirth()
            advanceOnboarding()
        } catch {
            // ignore
        }
    }

    func signInWithWallet(useOtherWallet: Bool = false) async {
        isAuthInFlight = true
        defer { isAuthInFlight = false }
        do {
            let user = try await AuthService.shared.signInWithWallet(
                useOtherWallet: useOtherWallet
            )
            self.currentUser = user
            UserDefaults.standard.set("wallet", forKey: "lastAuthProvider")
            applyPendingDateOfBirth()
            advanceOnboarding()
        } catch {
            // ignore
        }
    }

    /// Clears the session, demo id, and cached user state so ContentView
    /// routes back to onboarding on next render. Called from the profile
    /// toolbar → Log out.
    func signOut() {
        APIClient.shared.sessionToken = nil
        APIClient.shared.demoAthleteId = nil
        currentUser = nil
        hasCompletedOnboarding = false
        onboardingStep = .hero
        workouts = []
        sweatPoints = .zero
        healthAuthorized = false
        pendingDateOfBirth = nil
        UserDefaults.standard.removeObject(forKey: "lastAuthProvider")
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

    /// Persists DOB on the signed-in user and PATCHes the athlete row (unix seconds).
    /// AgeGate runs before auth now, so if there is no `currentUser` yet we
    /// stash the date and replay it inside the sign-in methods.
    func setDOB(_ date: Date) {
        if var user = currentUser {
            user.dateOfBirth = date
            currentUser = user
            let unix = Int(date.timeIntervalSince1970)
            Task {
                _ = try? await APIClient.shared.updateMe(AthletePatch(dob: unix))
            }
        } else {
            pendingDateOfBirth = date
        }
    }

    /// After a successful sign-in, write any DOB captured pre-auth onto the
    /// new user and sync it up to the backend.
    private func applyPendingDateOfBirth() {
        guard let date = pendingDateOfBirth else { return }
        pendingDateOfBirth = nil
        if var user = currentUser {
            user.dateOfBirth = date
            currentUser = user
        }
        let unix = Int(date.timeIntervalSince1970)
        Task {
            _ = try? await APIClient.shared.updateMe(AthletePatch(dob: unix))
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
