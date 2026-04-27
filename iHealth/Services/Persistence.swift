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

    nonisolated static func saveUser(_ user: User?) {
        writeQueue.async {
            let d = UserDefaults.standard
            if let user, let data = try? encoder.encode(user) {
                d.set(data, forKey: Key.currentUser)
            } else {
                d.removeObject(forKey: Key.currentUser)
            }
        }
    }

    nonisolated static func loadUser() -> User? {
        guard let data = UserDefaults.standard.data(forKey: Key.currentUser) else {
            return nil
        }
        return try? decoder.decode(User.self, from: data)
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
