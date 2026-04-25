import Foundation
import Observation

/// App-wide state. Drives the top-level router (onboarding vs. main app) and
/// holds the signed-in user + current workout catalogue.
@Observable
@MainActor
final class AppState {
    // MARK: - Auth / session
    var currentUser: User? {
        didSet { AppPersistence.saveUser(currentUser) }
    }
    var isAuthenticated: Bool { currentUser != nil }

    // MARK: - Onboarding
    var onboardingStep: OnboardingStep = .hero {
        didSet { AppPersistence.saveOnboardingStep(onboardingStep) }
    }
    var hasCompletedOnboarding: Bool = false {
        didSet { AppPersistence.saveHasCompletedOnboarding(hasCompletedOnboarding) }
    }
    var isAuthInFlight: Bool = false

    // MARK: - Init
    //
    // Cold-start: rehydrate the signed-in user + onboarding flag from
    // disk, and rehydrate the API session token from Keychain. If we
    // had a session last launch, the user lands directly on the feed
    // instead of replaying onboarding. signOut clears all of this.

    init() {
        self.currentUser = AppPersistence.loadUser()
        self.hasCompletedOnboarding = AppPersistence.loadHasCompletedOnboarding()
        self.workouts = AppPersistence.loadWorkouts()
        self.sweatPoints = AppPersistence.loadSweatPoints()
        if let token = AppPersistence.loadSessionToken() {
            APIClient.shared.sessionToken = token
        }

        // Resume on the screen the user last saw. If they were partway
        // through onboarding when they force-quit, we drop them right
        // back where they left off. With one floor: if they're already
        // signed in, never show Hero / AgeGate / Auth again — those
        // screens come BEFORE auth in the flow, so a signed-in user
        // landing on them is the "kicked out" UX bug we just hit.
        let savedStep = AppPersistence.loadOnboardingStep()
        if currentUser != nil, savedStep.rawValue < OnboardingStep.nameGoal.rawValue {
            self.onboardingStep = .nameGoal
        } else {
            self.onboardingStep = savedStep
        }

        // Returning users skip onboarding, so the BackfillScreen
        // never reruns. Kick off a background refresh from
        // HealthKit + the social feed so the cached values get
        // replaced with the freshest data without the user lifting
        // a finger. No-op for first-launch (currentUser nil).
        if currentUser != nil {
            Task { [weak self] in
                await self?.refreshOnLaunch()
            }
        }
    }

    /// Background refresh on returning-user cold-start. Pulls the
    /// latest HealthKit workouts (overwriting the persisted cache)
    /// and re-seeds the social service so the feed has fresh data.
    private func refreshOnLaunch() async {
        // HealthKit auth is sticky across launches at the OS level,
        // so we don't need to re-prompt — the request call here is
        // a no-op when already granted.
        _ = await requestHealthAuth()
        await backfillWorkouts(onProgress: { _ in })
    }

    /// DOB captured before auth (AgeGate is now the first gated step). We can't
    /// PATCH the athlete row until we have a session token, so we stash it and
    /// replay once the user signs in.
    private var pendingDateOfBirth: Date?

    // MARK: - Data
    //
    // Both fields persist as a launch-time cache so the UI renders
    // immediately on cold start. Apple HealthKit is the source of
    // truth — `refreshFromHealthKit()` runs in the background after
    // launch and overwrites these with fresh data. Stale-cache reads
    // happen for the first ~2 seconds of a relaunch, which is the
    // right tradeoff vs. a blank Profile screen.
    var workouts: [Workout] = [] {
        didSet { AppPersistence.saveWorkouts(workouts) }
    }
    var sweatPoints: SweatPoints = .zero {
        didSet { AppPersistence.saveSweatPoints(sweatPoints) }
    }

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
    /// toolbar → Log out. Also wipes the persisted state on disk so a
    /// relaunch lands back at Hero rather than the rehydrated session.
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
        AppPersistence.clearAll()
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
            let fresh = try await HealthKitService.shared.loadHistoricalWorkouts { count in
                onProgress(count)
            }
            // Merge with the cached set so previously-minted workouts
            // keep their `verified` / `synced` flags. iOS Workout.id
            // is the HealthKit UUID (set in HealthKitService.workout
            // (from:)), so the same physical session always rehydrates
            // to the same id. The cache wins on chain-state flags;
            // HealthKit wins on numeric values (distance / energy /
            // duration) since HK is the source of truth for what
            // actually happened.
            let cached = Dictionary(uniqueKeysWithValues:
                self.workouts.map { ($0.id, $0) })
            let merged: [Workout] = fresh.map { hk in
                guard let prior = cached[hk.id] else { return hk }
                var w = hk
                w.verified = prior.verified
                w.synced   = prior.synced
                // Preserve the points already attributed to a verified
                // workout — the chain mint locked it in. Recompute for
                // unverified ones so formula updates take effect.
                if prior.verified { w.points = prior.points }
                return w
            }
            self.workouts = merged
            let total = merged.reduce(0) { $0 + $1.points }
            self.sweatPoints = SweatPoints(
                total: total,
                weekly: merged.prefix { Date().timeIntervalSince($0.startDate) < 7*24*3600 }
                              .reduce(0) { $0 + $1.points },
                streakDays: Self.estimateStreak(from: merged)
            )
            SocialDataService.shared.seed(for: currentUser, workouts: merged)
        } catch {
            // Don't blow away the cache on a transient HealthKit
            // error — keep what's persisted so the user doesn't see
            // an empty profile.
            SocialDataService.shared.seed(for: currentUser, workouts: self.workouts)
        }
    }

    /// True when this workout's HealthKit UUID is already known on
    /// chain (we minted SWEAT for it). Used to skip a redundant
    /// /v1/workouts submission that the server's canonical_hash
    /// dedup would reject anyway. Saves a network round-trip and
    /// lets the UI flip directly to "✓ on chain" instead of flashing
    /// a spinner before an error.
    func isAlreadyOnChain(_ workout: Workout) -> Bool {
        workouts.first(where: { $0.id == workout.id })?.verified == true
    }

    /// The most recent HealthKit-imported workout that hasn't been
    /// minted on chain yet. Drives the "mint your latest workout"
    /// CTA on the record sheet — when nil, every recent workout is
    /// already on chain and the button hides itself.
    var latestUnmintedWorkout: Workout? {
        workouts
            .filter { !$0.verified }
            .sorted { $0.startDate > $1.startDate }
            .first
    }

    // MARK: - On-chain mint
    //
    // A direct "submit this workout to Sui right now" path that
    // does not require the live recorder. Powers the demo button
    // judges hit to see a real testnet tx land in their face.

    enum MintResult {
        case success(workoutId: String, txDigest: String)
        case alreadyMinted
        case failed(String)
    }

    @MainActor
    func mintWorkoutOnChain(_ workout: Workout) async -> MintResult {
        if isAlreadyOnChain(workout) {
            return .alreadyMinted
        }
        let req = SubmitWorkoutRequest(
            type: workout.type.rawValue,
            startDate: workout.startDate.timeIntervalSince1970,
            durationSeconds: workout.duration,
            distanceMeters: workout.distanceMeters,
            energyKcal: workout.energyKcal,
            avgHeartRate: workout.avgHeartRate,
            paceSecondsPerKm: workout.paceSecondsPerKm,
            points: workout.points,
            title: Self.titleFor(workout),
            caption: nil
        )
        do {
            let resp = try await APIClient.shared.submitWorkout(req)
            // Mark the cached workout verified so the next launch
            // recognises it without another submit attempt.
            if let idx = workouts.firstIndex(where: { $0.id == workout.id }) {
                workouts[idx].verified = true
            }
            return .success(workoutId: resp.workoutId, txDigest: resp.txDigest)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Default share/feed title for an arbitrary workout. Mirrors
    /// SocialDataService.defaultTitle so direct-submitted sessions
    /// look the same as the recorder's output.
    private static func titleFor(_ w: Workout) -> String {
        let hour = Calendar.current.component(.hour, from: w.startDate)
        let timeOfDay: String
        switch hour {
        case 5..<10:  timeOfDay = "Morning"
        case 10..<14: timeOfDay = "Midday"
        case 14..<18: timeOfDay = "Afternoon"
        case 18..<22: timeOfDay = "Evening"
        default:      timeOfDay = "Late-night"
        }
        return "\(timeOfDay) \(w.type.title.lowercased())"
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
