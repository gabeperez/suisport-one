import Foundation
import Observation

/// App-wide state. Drives the top-level router (onboarding vs. main app) and
/// holds the signed-in user + current workout catalogue.
@Observable
@MainActor
final class AppState {
    // MARK: - Auth / session
    /// Signed-in user. Hydrated from disk at init; setter writes
    /// through so a relaunch picks up the latest profile snapshot.
    var currentUser: User? {
        didSet { AppPersistence.saveUser(currentUser) }
    }
    var isAuthenticated: Bool { currentUser != nil }

    // MARK: - Onboarding
    var onboardingStep: OnboardingStep = .hero
    /// Set once the user finishes onboarding. Drives RootView's
    /// router so a signed-in returning user lands in the main app
    /// directly. Persisted to UserDefaults.
    var hasCompletedOnboarding: Bool = false {
        didSet { AppPersistence.saveHasCompletedOnboarding(hasCompletedOnboarding) }
    }
    var isAuthInFlight: Bool = false
    /// Last sign-in error message — drives the AuthScreen banner so we
    /// stop hiding real failures behind a silent mock fallback.
    var lastAuthError: String?
    /// Toggle in Profile → Settings. When ON, the seeded fixture feed
    /// + clubs + athletes stay visible: social.refresh() bails out
    /// early so server data doesn't overwrite the demo set. The
    /// FeedView's DEMO chip stays on too. Useful as a stage backup
    /// for showing rich social context without touching real data.
    var showDemoData: Bool = AppPersistence.loadShowDemoData() {
        didSet { AppPersistence.saveShowDemoData(showDemoData) }
    }

    init() {
        // Rehydrate from disk. We do this in the property initializer's
        // body via a 1:1 mirror — the didSets above also write back to
        // disk, but they're benign overwrites of the same value.
        let savedUser = AppPersistence.loadUser()
        let savedDone = AppPersistence.loadHasCompletedOnboarding()
        self.currentUser = savedUser
        self.hasCompletedOnboarding = savedDone
        // If we have a session, verify it's still valid against the
        // server and clear if expired. Fire-and-forget; the UI can
        // render immediately from the cached snapshot.
        if APIClient.shared.sessionToken != nil, savedUser != nil {
            Task { [weak self] in
                await self?.verifySessionOnLaunch()
            }
        }
    }

    /// Hits /v1/auth/whoami once at launch. If the server says the
    /// session is dead (401 or `authenticated: false`), tear down the
    /// cached state so the user sees onboarding instead of a stale
    /// "Hey, Athlete" header pointing at an expired account.
    private func verifySessionOnLaunch() async {
        do {
            let resp = try await APIClient.shared.fetchWhoami()
            if resp.authenticated == false {
                signOut()
            }
        } catch let api as APIError {
            if case .server(let code, _) = api, code == 401 {
                signOut()
            }
            // Other errors (transport, 5xx) are transient — keep the
            // cached session and let the next API call decide.
        } catch {
            // Network blip — leave the cached session alone.
        }
    }

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
        lastAuthError = nil
        defer { isAuthInFlight = false }
        do {
            let user = try await AuthService.shared.signInWithApple()
            self.currentUser = user
            UserDefaults.standard.set("apple", forKey: "lastAuthProvider")
            applyPendingDateOfBirth()
            advanceOnboarding()
        } catch AuthService.AuthError.cancelled {
            // user tapped cancel — no banner
        } catch {
            lastAuthError = describeAuthError(error)
        }
    }

    func signInWithGoogle() async {
        isAuthInFlight = true
        lastAuthError = nil
        defer { isAuthInFlight = false }
        do {
            let user = try await AuthService.shared.signInWithGoogle()
            self.currentUser = user
            UserDefaults.standard.set("google", forKey: "lastAuthProvider")
            applyPendingDateOfBirth()
            advanceOnboarding()
        } catch AuthService.AuthError.cancelled {
            // user tapped cancel — no banner
        } catch {
            lastAuthError = describeAuthError(error)
        }
    }

    func signInWithWallet(useOtherWallet: Bool = false) async {
        isAuthInFlight = true
        lastAuthError = nil
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
            lastAuthError = describeAuthError(error)
        }
    }

    private func describeAuthError(_ error: Error) -> String {
        if case AuthService.AuthError.failed(let msg) = error {
            return "Sign-in failed: \(msg)"
        }
        if let api = error as? APIError {
            switch api {
            case .server(let code, let body):
                return "Sign-in failed (HTTP \(code)). \(body.prefix(120))"
            case .transport: return "Sign-in failed: network error."
            case .notImplemented: return "Sign-in failed: not implemented."
            }
        }
        return "Sign-in failed: \(error.localizedDescription)"
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
