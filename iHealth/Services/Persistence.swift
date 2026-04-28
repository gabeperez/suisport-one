import Foundation
import Security

/// Persistence for sign-in state. Three pieces survive a relaunch so
/// the user doesn't walk through onboarding every time:
///
///   1. `sessionToken` (Keychain) — the bearer JWT issued by the
///      Worker on /v1/auth/session. Protected with `WhenUnlocked`
///      access so it's available after first device unlock.
///   2. `currentUser` snapshot (UserDefaults) — display name, handle,
///      Sui address, photo URL. Cheap to write, instantly available
///      at launch so the UI can render without waiting on the
///      network.
///   3. `hasCompletedOnboarding` (UserDefaults) — a single Bool that
///      drives the root router (RootView). Set to true the first
///      time the user finishes the onboarding flow.
///
/// Deliberately small. We do NOT persist:
///   - workouts (refetched from /v1/me/workouts each launch — D1 is
///     the source of truth)
///   - sweat balances (refetched from /v1/sui/balance/<addr> + /sweat)
///   - feed / clubs / athletes (SocialDataService.refresh() rehydrates)
///   - onboardingStep (intentionally NOT persisted — caused regressions
///     in the closed polish PR; signed-in users never see onboarding
///     anyway because hasCompletedOnboarding short-circuits the router)
/// All methods are `nonisolated` so they can be called from any
/// actor context — including APIClient's property initializer, which
/// runs in a nonisolated context. Without the explicit annotation,
/// Swift 6 strict concurrency infers `@MainActor` from the project's
/// default actor and APIClient's call site warns about cross-actor
/// access.
///
/// Writes are dispatched to a serial background queue so didSets in
/// the @MainActor AppState don't block UI taps with synchronous
/// JSON encode + UserDefaults flush + Keychain calls. Reads stay
/// synchronous — they only happen at launch and need to return a
/// value to the caller.
enum AppPersistence {
    // All key/queue/encoder constants are `nonisolated`. Without it,
    // Swift 6 infers @MainActor from the project default and the
    // nonisolated save/load methods can't reference them. The Sendable
    // types (DispatchQueue, JSONEncoder, JSONDecoder) don't need
    // `(unsafe)` — Swift can prove cross-actor access is safe.
    private enum Key {
        nonisolated static let currentUser = "SuiSportONE.currentUser.v1"
        nonisolated static let myAthlete = "SuiSportONE.myAthlete.v1"
        nonisolated static let cachedFeed = "SuiSportONE.cachedFeed.v1"
        nonisolated static let cachedAthletes = "SuiSportONE.cachedAthletes.v1"
        nonisolated static let claimedTrophyKeys = "SuiSportONE.claimedTrophyKeys.v1"
        nonisolated static let hasCompletedOnboarding = "SuiSportONE.hasCompletedOnboarding"
        nonisolated static let showDemoData = "SuiSportONE.showDemoData"
    }
    nonisolated private static let keychainService = "gimme.coffee.iHealth.session"
    nonisolated private static let keychainAccount = "session-jwt"
    /// Serial background queue for writes. Keeps disk writes off the
    /// main thread while preserving order so a save followed by a
    /// load (rare) sees the latest value.
    nonisolated private static let writeQueue = DispatchQueue(
        label: "gimme.coffee.iHealth.persistence",
        qos: .utility
    )

    nonisolated private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()
    nonisolated private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    // MARK: - currentUser
    //
    // Marked `@MainActor` because User's synthesized Codable conformance
    // is MainActor-isolated (project default actor) and can't be used
    // from a nonisolated context in Swift 6 strict mode. Both call
    // sites (AppState.init + AppState.currentUser didSet) are already
    // MainActor, so this is a tightening of the contract that costs
    // nothing. UserDefaults writes are fast + in-memory + delayed-flush,
    // so we don't lose meaningful main-thread headroom here.

    @MainActor static func saveUser(_ user: User?) {
        let d = UserDefaults.standard
        if let user, let data = try? encoder.encode(user) {
            d.set(data, forKey: Key.currentUser)
        } else {
            d.removeObject(forKey: Key.currentUser)
        }
    }

    @MainActor static func loadUser() -> User? {
        guard let data = UserDefaults.standard.data(forKey: Key.currentUser) else {
            return nil
        }
        return try? decoder.decode(User.self, from: data)
    }

    // MARK: - my Athlete (social profile)
    //
    // Persisted in addition to currentUser because the social `me` row
    // carries the user-customized fields (handle, bio, photo, tones,
    // showcased trophies) that aren't in `User`. Without this snapshot,
    // a relaunch with a slow `/me` round-trip shows a bare stub built
    // from User's displayName until refresh() lands — which on flaky
    // networks can take many seconds.

    /// Strip raw `photoData` bytes off an athlete before persisting —
    /// the canonical avatar source is `photoURL` (R2), and the
    /// PhotosPicker hands back full-resolution HEIC/PNG that would
    /// blow past UserDefaults' 4MB write limit. We keep `photoData`
    /// only when there's no `photoURL` yet (mid-upload) so the local
    /// preview still renders on relaunch.
    private static func stripPhotoIfRedundant(_ athlete: Athlete) -> Athlete {
        var copy = athlete
        if let url = copy.photoURL, !url.isEmpty {
            copy.photoData = nil
        } else if let data = copy.photoData, data.count > 200_000 {
            // No URL yet but the bytes are huge — drop them anyway
            // rather than crash UserDefaults. Worst case the user
            // sees the gradient fallback for a few seconds until
            // the next /me refresh hands back the photoURL.
            copy.photoData = nil
        }
        return copy
    }

    @MainActor static func saveMe(_ athlete: Athlete?) {
        let d = UserDefaults.standard
        if let athlete {
            let pruned = stripPhotoIfRedundant(athlete)
            if let data = try? encoder.encode(pruned) {
                d.set(data, forKey: Key.myAthlete)
            }
        } else {
            d.removeObject(forKey: Key.myAthlete)
        }
    }

    @MainActor static func loadMe() -> Athlete? {
        guard let data = UserDefaults.standard.data(forKey: Key.myAthlete) else {
            return nil
        }
        // Defensive: an oversized blob from a pre-fix build (where
        // we baked full-res photoData) doesn't fit UserDefaults'
        // 4MB write cap. If we ever see one, drop it on read so the
        // next saveMe writes a clean trimmed copy.
        if data.count > 1_000_000 {
            UserDefaults.standard.removeObject(forKey: Key.myAthlete)
            return nil
        }
        return try? decoder.decode(Athlete.self, from: data)
    }

    // MARK: - cached feed (top page)
    //
    // Persisting the most recent feed page lets the app render real
    // content on launch instead of a blank list while the network
    // refresh is in flight. Only the top page is stored — pagination
    // re-fetches old pages on demand. Kudos/comment state is whatever
    // we had last refresh; refresh() overwrites within ~1s of launch.

    @MainActor static func saveFeed(_ items: [FeedItem]) {
        let d = UserDefaults.standard
        // Cap at 30 to bound size — same as the page size used by
        // /feed?limit=30. Also strip embedded photoData bytes off
        // each item's athlete reference; without this, a logged-in
        // user's avatar bytes get duplicated across every feed item
        // and we blow past UserDefaults' 4MB write limit.
        let pruned = items.prefix(30).map { item -> FeedItem in
            var copy = item
            copy.athlete = stripPhotoIfRedundant(copy.athlete)
            return copy
        }
        if let data = try? encoder.encode(Array(pruned)) {
            d.set(data, forKey: Key.cachedFeed)
        }
    }

    @MainActor static func loadFeed() -> [FeedItem] {
        guard let data = UserDefaults.standard.data(forKey: Key.cachedFeed) else {
            return []
        }
        // Defensive: pre-fix builds wrote feeds with photo bytes
        // baked into every athlete (~6MB+). Drop oversized blobs
        // on read so the next saveFeed lands a clean small copy.
        if data.count > 3_500_000 {
            UserDefaults.standard.removeObject(forKey: Key.cachedFeed)
            return []
        }
        guard let items = try? decoder.decode([FeedItem].self, from: data)
        else { return [] }
        return items
    }

    @MainActor static func clearFeed() {
        UserDefaults.standard.removeObject(forKey: Key.cachedFeed)
    }

    // MARK: - cached athletes (harvested from feed)
    //
    // Profile taps from feed cards resolve through the harvested
    // athletes list. Without this cache, tapping someone's avatar
    // before refresh() lands renders an empty AthleteProfileView.

    @MainActor static func saveAthletes(_ athletes: [Athlete]) {
        let d = UserDefaults.standard
        let pruned = athletes.prefix(60).map(stripPhotoIfRedundant)
        if let data = try? encoder.encode(Array(pruned)) {
            d.set(data, forKey: Key.cachedAthletes)
        }
    }

    @MainActor static func loadAthletes() -> [Athlete] {
        guard let data = UserDefaults.standard.data(forKey: Key.cachedAthletes),
              let athletes = try? decoder.decode([Athlete].self, from: data)
        else { return [] }
        return athletes
    }

    @MainActor static func clearAthletes() {
        UserDefaults.standard.removeObject(forKey: Key.cachedAthletes)
    }

    // MARK: - claimed trophy keys
    //
    // Persists which trophies the user has claimed so the unlock
    // survives a relaunch. Keyed on the trophy's stable string key
    // (e.g. "5k-finisher") rather than its UUID — UUIDs are minted
    // fresh on each seed, but the criterion identity is permanent.

    @MainActor static func saveClaimedTrophyKeys(_ keys: Set<String>) {
        let d = UserDefaults.standard
        if let data = try? encoder.encode(Array(keys)) {
            d.set(data, forKey: Key.claimedTrophyKeys)
        }
    }

    @MainActor static func loadClaimedTrophyKeys() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: Key.claimedTrophyKeys),
              let keys = try? decoder.decode([String].self, from: data)
        else { return [] }
        return Set(keys)
    }

    @MainActor static func clearClaimedTrophyKeys() {
        UserDefaults.standard.removeObject(forKey: Key.claimedTrophyKeys)
    }

    // MARK: - onboarding completion

    nonisolated static func saveHasCompletedOnboarding(_ value: Bool) {
        writeQueue.async {
            UserDefaults.standard.set(value, forKey: Key.hasCompletedOnboarding)
        }
    }

    nonisolated static func loadHasCompletedOnboarding() -> Bool {
        UserDefaults.standard.bool(forKey: Key.hasCompletedOnboarding)
    }

    // MARK: - showDemoData

    nonisolated static func saveShowDemoData(_ value: Bool) {
        writeQueue.async {
            UserDefaults.standard.set(value, forKey: Key.showDemoData)
        }
    }

    nonisolated static func loadShowDemoData() -> Bool {
        UserDefaults.standard.bool(forKey: Key.showDemoData)
    }

    // MARK: - sessionToken (Keychain)

    nonisolated static func saveSessionToken(_ token: String?) {
        // Keychain SecItemAdd/Delete can take 50–100ms — defer off
        // the main thread so AppState mutations don't hitch UI.
        writeQueue.async {
            let baseQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecAttrAccount as String: keychainAccount,
            ]
            SecItemDelete(baseQuery as CFDictionary)

            guard let token, !token.isEmpty,
                  let data = token.data(using: .utf8) else { return }

            var add = baseQuery
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    nonisolated static func loadSessionToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8)
        else { return nil }
        return token
    }
}
