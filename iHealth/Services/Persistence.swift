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
enum AppPersistence {
    private enum Key {
        static let currentUser = "SuiSportONE.currentUser.v1"
        static let hasCompletedOnboarding = "SuiSportONE.hasCompletedOnboarding"
    }
    private static let keychainService = "gimme.coffee.iHealth.session"
    private static let keychainAccount = "session-jwt"

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    // MARK: - currentUser

    static func saveUser(_ user: User?) {
        let d = UserDefaults.standard
        if let user, let data = try? encoder.encode(user) {
            d.set(data, forKey: Key.currentUser)
        } else {
            d.removeObject(forKey: Key.currentUser)
        }
    }

    static func loadUser() -> User? {
        guard let data = UserDefaults.standard.data(forKey: Key.currentUser) else {
            return nil
        }
        return try? decoder.decode(User.self, from: data)
    }

    // MARK: - onboarding completion

    static func saveHasCompletedOnboarding(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: Key.hasCompletedOnboarding)
    }

    static func loadHasCompletedOnboarding() -> Bool {
        UserDefaults.standard.bool(forKey: Key.hasCompletedOnboarding)
    }

    // MARK: - sessionToken (Keychain)

    static func saveSessionToken(_ token: String?) {
        // Always delete first so we can replace cleanly without an
        // errSecDuplicateItem ping-pong.
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

    static func loadSessionToken() -> String? {
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
