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

    /// Single-instance bridge for non-View / non-AppState callers that
    /// need to reach back into AppState (e.g. SocialDataService
    /// reconciling the server-side Sweat ledger after a /me refresh).
    /// The app only ever has one instance — assigned on init.
    static weak var shared: AppState?

    init() {
        Self.shared = self
        // Rehydrate from disk. We do this in the property initializer's
        // body via a 1:1 mirror — the didSets above also write back to
        // disk, but they're benign overwrites of the same value.
        let savedUser = AppPersistence.loadUser()
        let savedDone = AppPersistence.loadHasCompletedOnboarding()
        self.currentUser = savedUser
        self.hasCompletedOnboarding = savedDone

        // If we have a persisted user, seed the social fixtures
        // synchronously so the feed/clubs/challenges show up
        // immediately on launch — without this, a returning user
        // who skips onboarding (because hasCompletedOnboarding=true)
        // sees an empty app until BackfillScreen would have run
        // (which it doesn't, because we skipped onboarding). The
        // seed call is guarded so a fresh-onboarding flow that
        // already seeded won't double-seed.
        if savedUser != nil {
            SocialDataService.shared.seed(for: savedUser, workouts: [])
        }

        // Background: verify session validity + reload HealthKit
        // history so workouts + sweatPoints repopulate after relaunch.
        // Both kick off after a tiny yield so SwiftUI gets the first
        // paint out before we hit the network and the (heavy) HealthKit
        // historical query — otherwise the user sees a frozen UI for
        // the launch wall-time of those calls.
        if APIClient.shared.sessionToken != nil, savedUser != nil {
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 150_000_000)
                await self?.verifySessionOnLaunch()
                // HealthKit historical fetch is the heaviest piece;
                // give the user a beat with a usable UI before we
                // start it so taps register immediately.
                try? await Task.sleep(nanoseconds: 350_000_000)
                await self?.rehydrateWorkoutsOnLaunch()
            }
        }
    }

    /// After session verification, reload the user's HealthKit
    /// history so app.workouts + app.sweatPoints aren't empty on
    /// a relaunch that skipped onboarding. Silent on HealthKit
    /// failure — the seeded fixtures already cover the social
    /// surface; the workouts list just stays empty until the user
    /// records a new session.
    private func rehydrateWorkoutsOnLaunch() async {
        guard currentUser != nil else { return }
        await backfillWorkouts { _ in }
        // After local cache is restored, ask the server which
        // workouts are on chain. Fills in digests we don't have
        // locally (fresh install, device swap, cleared cache) so
        // the user doesn't see "Claim Sweat → 422" loops on
        // already-minted workouts.
        await reconcileWorkoutsFromServer()
    }

    /// Match server-known on-chain workouts back to local HealthKit
    /// workouts and fill in any missing digests in the local cache.
    /// Matching uses the same canonical bucket the server's fraud
    /// module uses for dedupe — `(type, start_minute, duration_min,
    /// distance_10m)` — so a HealthKit workout that produced a
    /// server row is reliably re-paired here.
    @MainActor
    func reconcileWorkoutsFromServer() async {
        guard currentUser != nil else { return }
        guard let resp = try? await APIClient.shared.fetchMyWorkouts() else { return }
        var newCache = workoutDigestCache
        var matched = 0
        for entry in resp.workouts {
            let serverStartMin = Int(entry.startDate / 60)
            let serverDurMin = Int(entry.durationSeconds / 60.0)
            let serverDist10m = Int(((entry.distanceMeters ?? 0) / 10).rounded()) * 10
            for w in workouts where newCache[w.id] == nil {
                let localStartMin = Int(w.startDate.timeIntervalSince1970 / 60)
                let localDurMin = Int(w.duration / 60.0)
                let localDist10m = Int(((w.distanceMeters ?? 0) / 10).rounded()) * 10
                if localStartMin == serverStartMin
                    && localDurMin == serverDurMin
                    && localDist10m == serverDist10m
                    && w.type.rawValue == entry.type {
                    newCache[w.id] = AppPersistence.WorkoutDigestRecord(
                        digest: entry.txDigest,
                        walrusBlobId: entry.walrusBlobId
                    )
                    matched += 1
                    break
                }
            }
        }
        guard matched > 0 else { return }
        workoutDigestCache = newCache
        // Re-attach the just-discovered digests onto the in-memory
        // workouts list so the UI flips immediately without waiting
        // for the next backfill.
        let cache = newCache
        workouts = workouts.map { w in
            guard w.suiTxDigest == nil, let record = cache[w.id] else { return w }
            var copy = w
            copy.suiTxDigest = record.digest
            copy.walrusBlobId = record.walrusBlobId
            copy.verified = true
            return copy
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
    /// Workout IDs the server told us are already saved (HTTP 422
    /// duplicate_submission). We don't have the real Sui tx digest
    /// for these on iOS, but knowing the workout is on chain lets
    /// us flip the verified strip on without another network call.
    /// Persisted across launches so a user doesn't see the same
    /// "Claim Sweat → 422" loop after a relaunch.
    var alreadyLoggedWorkoutIDs: Set<UUID> =
        AppPersistence.loadAlreadyLoggedWorkoutIDs() {
        didSet { AppPersistence.saveAlreadyLoggedWorkoutIDs(alreadyLoggedWorkoutIDs) }
    }

    /// Persisted cache of `(suiTxDigest, walrusBlobId)` per workout
    /// id. HealthKit doesn't carry our chain receipts so without this
    /// cache, every relaunch re-presents "Claim Sweat" for workouts
    /// the user already claimed. Survives across launches; cleared
    /// on signOut.
    var workoutDigestCache: [UUID: AppPersistence.WorkoutDigestRecord]
        = AppPersistence.loadWorkoutDigests()
    {
        didSet { AppPersistence.saveWorkoutDigests(workoutDigestCache) }
    }

    /// Local ledger of Sweat credited (mints, including bonuses) and
    /// redeemed (sample tickets, drops). Persisted across launches —
    /// the only durable record of "what the chain actually paid out
    /// vs what was spent." See SweatLedger for math + intent.
    var sweatLedger: SweatLedger = AppPersistence.loadSweatLedger() ?? .zero {
        didSet { AppPersistence.saveSweatLedger(sweatLedger) }
    }

    /// Set of fighter athleteIds the user has unlocked the community
    /// for. Drives the locked/unlocked state in CommunityTab. Phase 1
    /// is local-only; Phase 2 moves authoritative state to D1.
    var communityMemberships: Set<String> = AppPersistence.loadCommunityMemberships() {
        didSet { AppPersistence.saveCommunityMemberships(communityMemberships) }
    }

    /// Mark a fighter's community as unlocked for the current user.
    /// Idempotent — re-unlocking a community is a no-op (no double
    /// Sweat charge, since the caller's `recordRedemption` is the
    /// source of truth on cost).
    func unlockCommunity(_ fighterId: String) {
        guard !communityMemberships.contains(fighterId) else { return }
        communityMemberships.insert(fighterId)
    }

    /// Per-fighter training camp progress. Each entry tracks which
    /// sessions of that fighter's plan the user has completed, with
    /// strict sequential ordering — `currentSessionIndex(in:)` is
    /// always the lowest unfinished session.
    var trainingProgress: [String: UserTrainingProgress] = AppPersistence.loadTrainingProgress() {
        didSet { AppPersistence.saveTrainingProgress(trainingProgress) }
    }

    /// Read-only view of the user's progress for a given plan.
    /// Returns a zero-completed scaffold for plans that haven't been
    /// started yet — no side effects, safe to call from any view's
    /// body.
    func progress(for plan: FighterTrainingPlan) -> UserTrainingProgress {
        trainingProgress[plan.id] ?? UserTrainingProgress(
            fighterId: plan.id,
            completedSessionKeys: [],
            startedAt: .now,
            lastCompletedAt: nil
        )
    }

    /// Mark a session complete for the given fighter's plan. Only
    /// advances when the session being marked is the *current* one
    /// (sequential progression — the user can't tap a future session
    /// to skip ahead). Creates the progress record lazily on first
    /// completion. Returns `true` if the camp just finished as a
    /// result, so the caller can fire the auto-unlock community
    /// celebration.
    @discardableResult
    func completeSession(
        _ session: TrainingSession,
        in plan: FighterTrainingPlan
    ) -> Bool {
        var current = trainingProgress[plan.id] ?? UserTrainingProgress(
            fighterId: plan.id,
            completedSessionKeys: [],
            startedAt: .now,
            lastCompletedAt: nil
        )
        guard !current.completedSessionKeys.contains(session.stableKey) else { return false }
        guard current.currentSessionIndex(in: plan) == session.index else { return false }
        current.completedSessionKeys.insert(session.stableKey)
        current.lastCompletedAt = .now
        trainingProgress[plan.id] = current

        // Auto-unlock the community when every session has been
        // completed — closes the "train like them" loop from Phase 1.
        if current.isComplete(in: plan) {
            unlockCommunity(plan.id)
            return true
        }
        return false
    }

    /// All plans the user has at least one completed (or started)
    /// session in — drives the "Training Plans" section on
    /// ProfileView and the Continue-camp menu in RecordSheet.
    func startedTrainingPlans(in plans: [String: FighterTrainingPlan]) -> [(plan: FighterTrainingPlan, progress: UserTrainingProgress)] {
        plans.values
            .compactMap { plan in
                guard let p = trainingProgress[plan.id] else { return nil }
                return (plan, p)
            }
            .sorted { $0.progress.lastCompletedAt ?? $0.progress.startedAt > $1.progress.lastCompletedAt ?? $1.progress.startedAt }
    }

    /// Add a successful mint's `pointsMinted` (server-final, includes
    /// bonuses) to the credited side of the ledger.
    func recordMintReward(_ pointsMinted: Int) {
        guard pointsMinted > 0 else { return }
        sweatLedger.credited += pointsMinted
    }

    /// Add a successful redemption's `costPoints` to the redeemed
    /// side of the ledger.
    func recordRedemption(_ costPoints: Int) {
        guard costPoints > 0 else { return }
        sweatLedger.redeemed += costPoints
    }

    /// Reconcile the local ledger against server-canonical values
    /// from /me. Only adopts the larger of {local, server} for each
    /// field — protects against a stale server read stomping a
    /// just-recorded local mint, while still letting the server
    /// catch us up after a fresh install or a different device.
    func reconcileSweatLedger(credited: Int?, redeemed: Int?) {
        var current = sweatLedger
        var changed = false
        if let c = credited, c > current.credited {
            current.credited = c
            changed = true
        }
        if let r = redeemed, r > current.redeemed {
            current.redeemed = r
            changed = true
        }
        if changed { sweatLedger = current }
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

    /// Called when the user navigates away from AuthScreen mid-flow
    /// (e.g. back-button after tapping Connect Sui Wallet but before
    /// Slush returns). Cancels any pending wallet continuation and
    /// resets the in-flight flag so the spinner doesn't get stuck.
    /// Submit a workout from local history (HealthKit backfill) to the
    /// chain. Builds the SubmitWorkoutRequest from the Workout, posts
    /// to /v1/workouts, and updates the matching entry in `workouts`
    /// with the returned tx digest + walrus blob id so the row can
    /// flip from "mintable" → "on chain ↗" without a refresh.
    @MainActor
    func mintWorkout(_ workout: Workout) async throws -> SubmitWorkoutResponse {
        // Sanitize paceSecondsPerKm before submit — Apple Health
        // synthesizes absurd paces for low-distance walks (a 20-meter
        // amble over 30 min computes to 90,000 sec/km), which busts
        // the server's Zod cap of 7200. Drop the field when it's
        // out of range; the server re-derives pace from duration +
        // distance for its fraud check anyway.
        let safePace: Double? = {
            guard let p = workout.paceSecondsPerKm else { return nil }
            return (p > 0 && p <= 7200) ? p : nil
        }()
        let req = SubmitWorkoutRequest(
            type: workout.type.rawValue,
            startDate: workout.startDate.timeIntervalSince1970,
            durationSeconds: workout.duration,
            distanceMeters: workout.distanceMeters,
            energyKcal: workout.energyKcal,
            avgHeartRate: workout.avgHeartRate,
            paceSecondsPerKm: safePace,
            points: workout.points,
            title: defaultTitle(for: workout),
            caption: nil
        )
        let resp = try await APIClient.shared.submitWorkout(req)
        // Only treat as on-chain if the worker actually ran the chain
        // step (digest doesn't start with `pending_`). Stub mode still
        // returns a placeholder we don't want to deep-link to.
        if !resp.txDigest.hasPrefix("pending_") {
            if let idx = workouts.firstIndex(where: { $0.id == workout.id }) {
                workouts[idx].suiTxDigest = resp.txDigest
                workouts[idx].walrusBlobId = resp.walrusBlobId
                workouts[idx].verified = true
            }
            // Persist the digest so a relaunch rehydrates this
            // workout as on-chain instead of falsely offering
            // "Claim Sweat" again.
            workoutDigestCache[workout.id] = .init(
                digest: resp.txDigest,
                walrusBlobId: resp.walrusBlobId
            )
        }
        return resp
    }

    private func defaultTitle(for w: Workout) -> String {
        let hour = Calendar.current.component(.hour, from: w.startDate)
        let when: String
        switch hour {
        case 5..<10: when = "Morning"
        case 10..<14: when = "Midday"
        case 14..<18: when = "Afternoon"
        case 18..<22: when = "Evening"
        default: when = "Late-night"
        }
        return "\(when) \(w.type.title.lowercased())"
    }

    func cancelPendingAuth() {
        WalletConnectBridge.shared.cancelPending()
        isAuthInFlight = false
        lastAuthError = nil
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
        // Clear the cached social profile so the next user to sign
        // in on this device doesn't inherit the previous person's
        // handle, photo, and showcase from disk. Same goes for the
        // cached feed + athletes — they were derived from the prior
        // session's auth.
        AppPersistence.saveMe(nil)
        AppPersistence.clearFeed()
        AppPersistence.clearAthletes()
        AppPersistence.clearClaimedTrophyKeys()
        AppPersistence.clearSweatLedger()
        sweatLedger = .zero
        AppPersistence.clearCommunityMemberships()
        communityMemberships = []
        AppPersistence.clearTrainingProgress()
        trainingProgress = [:]
        AppPersistence.clearWorkoutDigests()
        workoutDigestCache = [:]
        AppPersistence.clearAlreadyLoggedWorkoutIDs()
        alreadyLoggedWorkoutIDs = []
        SocialDataService.shared.clearMe()
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
            let raw = try await HealthKitService.shared.loadHistoricalWorkouts { count in
                onProgress(count)
            }
            // Re-attach previously-minted chain digests to freshly
            // loaded HealthKit workouts. Without this, every
            // relaunch presents "Claim Sweat" for already-on-chain
            // workouts (HealthKit doesn't carry our Sui receipts)
            // and the user only learns it's a duplicate after the
            // server 422s.
            let cache = workoutDigestCache
            let workouts: [Workout] = raw.map { w in
                guard let record = cache[w.id] else { return w }
                var copy = w
                copy.suiTxDigest = record.digest
                copy.walrusBlobId = record.walrusBlobId
                copy.verified = true
                return copy
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
            // seed() is a no-op past first launch; explicitly refresh
            // the workout-derived shelves so trophies/streak/PRs
            // reflect the freshly-loaded HealthKit history. Without
            // this, claimable trophies would stay locked after
            // rehydrate even though the user has the qualifying runs.
            SocialDataService.shared.refreshFromWorkouts(workouts)
            // Surface any workout the user finished while the app
            // was backgrounded (e.g. a watch session that synced
            // mid-presentation) at the top of the feed so the
            // celebration claim flow is one tap away.
            SocialDataService.shared.appendNewUserWorkouts(workouts)
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
