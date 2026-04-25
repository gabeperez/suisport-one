import Foundation
import Security

/// Persistence layer for app-launch state.
///
/// Two backings:
///   - `UserDefaults` for non-sensitive user-visible state
///     (`hasCompletedOnboarding`, the `User` profile struct itself,
///     `lastAuthProvider`).
///   - `Keychain` for the session bearer token. Tokens grant API
///     access on behalf of the user — they do not belong in
///     UserDefaults plist files that ship in iCloud backups.
///
/// All accessors are synchronous and main-actor-safe; values are
/// only used during cold-start and in response to user actions, so
/// the I/O cost is negligible.
enum AppPersistence {

    // MARK: - Keys

    enum K {
        static let hasCompletedOnboarding = "SuiSportONE.hasCompletedOnboarding"
        static let onboardingStep         = "SuiSportONE.onboardingStep"
        static let currentUser            = "SuiSportONE.currentUser.v1"
        static let workouts               = "SuiSportONE.workouts.v1"
        static let sweatPoints            = "SuiSportONE.sweatPoints.v1"
        static let lastAuthProvider       = "lastAuthProvider"  // historical
    }

    // MARK: - hasCompletedOnboarding

    static func saveHasCompletedOnboarding(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: K.hasCompletedOnboarding)
    }

    static func loadHasCompletedOnboarding() -> Bool {
        UserDefaults.standard.bool(forKey: K.hasCompletedOnboarding)
    }

    // MARK: - onboardingStep
    //
    // Persisted as the rawValue (Int) of the OnboardingStep enum so
    // a user who quits mid-flow lands back on the same screen
    // instead of replaying from Hero. Default = .hero on miss.

    static func saveOnboardingStep(_ step: OnboardingStep) {
        UserDefaults.standard.set(step.rawValue, forKey: K.onboardingStep)
    }

    static func loadOnboardingStep() -> OnboardingStep {
        // UserDefaults.integer returns 0 on miss, which happens to be
        // .hero — the right default when there's no prior state.
        let raw = UserDefaults.standard.integer(forKey: K.onboardingStep)
        return OnboardingStep(rawValue: raw) ?? .hero
    }

    // MARK: - User profile struct

    /// JSON encoder/decoder configured with secondsSince1970 dates so
    /// `User.createdAt` / `User.dateOfBirth` survive launches without
    /// timezone weirdness.
    private static let coder: (JSONEncoder, JSONDecoder) = {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .secondsSince1970
        return (enc, dec)
    }()

    static func saveUser(_ user: User?) {
        guard let user else {
            UserDefaults.standard.removeObject(forKey: K.currentUser)
            return
        }
        if let data = try? coder.0.encode(user) {
            UserDefaults.standard.set(data, forKey: K.currentUser)
        }
    }

    static func loadUser() -> User? {
        guard let data = UserDefaults.standard.data(forKey: K.currentUser)
        else { return nil }
        return try? coder.1.decode(User.self, from: data)
    }

    // MARK: - Workouts (HealthKit cache)
    //
    // The authoritative source is Apple HealthKit; this persistence
    // is only a launch-time cache so the UI has something to render
    // while the background re-backfill runs. Stale data is fine —
    // it gets overwritten the moment HealthKit returns fresh values.

    static func saveWorkouts(_ workouts: [Workout]) {
        if let data = try? coder.0.encode(workouts) {
            UserDefaults.standard.set(data, forKey: K.workouts)
        }
    }

    static func loadWorkouts() -> [Workout] {
        guard let data = UserDefaults.standard.data(forKey: K.workouts)
        else { return [] }
        return (try? coder.1.decode([Workout].self, from: data)) ?? []
    }

    // MARK: - SweatPoints

    static func saveSweatPoints(_ pts: SweatPoints) {
        if let data = try? coder.0.encode(pts) {
            UserDefaults.standard.set(data, forKey: K.sweatPoints)
        }
    }

    static func loadSweatPoints() -> SweatPoints {
        guard let data = UserDefaults.standard.data(forKey: K.sweatPoints)
        else { return .zero }
        return (try? coder.1.decode(SweatPoints.self, from: data)) ?? .zero
    }

    // MARK: - Session token (Keychain)

    /// Bearer token returned by `/v1/auth/session`. Stored in the
    /// keychain because anyone holding it can act as the user against
    /// the backend; UserDefaults plist would put it in iCloud backup.
    /// AccessibleAfterFirstUnlock so background tasks (workout retry,
    /// push handling) can still read it after a reboot.
    static func saveSessionToken(_ token: String?) {
        Keychain.set("sessionToken", value: token)
    }

    static func loadSessionToken() -> String? {
        Keychain.get("sessionToken")
    }

    // MARK: - Reset

    /// Clear every persisted login artifact. Called from signOut so a
    /// fresh launch routes back to onboarding cleanly.
    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: K.hasCompletedOnboarding)
        UserDefaults.standard.removeObject(forKey: K.onboardingStep)
        UserDefaults.standard.removeObject(forKey: K.currentUser)
        UserDefaults.standard.removeObject(forKey: K.workouts)
        UserDefaults.standard.removeObject(forKey: K.sweatPoints)
        UserDefaults.standard.removeObject(forKey: K.lastAuthProvider)
        Keychain.delete("sessionToken")
    }
}

// MARK: - Tiny Keychain wrapper
//
// Generic password class, item key = "SuiSportONE.<account>". No
// access groups — single-app keychain. Returns nil on any error
// rather than throwing, since the UI handles the "no session" case
// already (kicks back to auth).

private enum Keychain {
    private static let service = "gimme.coffee.iHealth.suisportone"

    static func set(_ account: String, value: String?) {
        let query: [String: Any] = [
            kSecClass as String:           kSecClassGenericPassword,
            kSecAttrService as String:     service,
            kSecAttrAccount as String:     account,
        ]
        SecItemDelete(query as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return }
        let attrs: [String: Any] = [
            kSecClass as String:           kSecClassGenericPassword,
            kSecAttrService as String:     service,
            kSecAttrAccount as String:     account,
            kSecValueData as String:       data,
            kSecAttrAccessible as String:  kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(attrs as CFDictionary, nil)
    }

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:           kSecClassGenericPassword,
            kSecAttrService as String:     service,
            kSecAttrAccount as String:     account,
            kSecReturnData as String:      true,
            kSecMatchLimit as String:      kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data,
              let str = String(data: data, encoding: .utf8)
        else { return nil }
        return str
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String:           kSecClassGenericPassword,
            kSecAttrService as String:     service,
            kSecAttrAccount as String:     account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
