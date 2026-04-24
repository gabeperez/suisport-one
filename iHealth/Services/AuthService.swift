import Foundation
import AuthenticationServices
import CryptoKit

/// Authentication service.
///
/// In production this calls the SuiSport backend which wraps Enoki:
///   POST /auth/session { idToken, provider }
///     -> backend exchanges OAuth JWT via Enoki /zklogin/zkp
///     -> backend derives/returns the user's Sui address (deterministic via salt server)
///     -> returns { sessionJwt, suiAddress, displayName, avatarUrl }
///
/// For now this is a mock that preserves the real flow shape so swapping the
/// backend call in later is a one-file change.
@MainActor
final class AuthService: NSObject {
    static let shared = AuthService()

    enum AuthError: Error { case cancelled, failed(String) }

    // MARK: - Public API

    /// Sign in with Apple. Pulls the real `identityToken` JWT from the
    /// credential and exchanges it via `/v1/auth/session`. Backend does
    /// Enoki zkLogin if configured; otherwise returns a deterministic
    /// mock address. We fall back to the local-mock path on network /
    /// backend errors so the app is usable offline.
    func signInWithApple() async throws -> User {
        let credential = try await requestAppleCredential()
        let name = Self.displayName(from: credential)
        let subject = credential.user

        guard let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else {
            // Rare: Apple returned a credential with no identity token.
            // Fall back to offline mock.
            return await mintMockSession(provider: .apple, subject: subject, name: name)
        }
        return await exchangeIdToken(provider: .apple, idToken: idToken,
                                     displayName: name, fallbackSubject: subject)
    }

    /// Sign in with Google. Still mock — wiring the Google Sign-In SDK
    /// is tracked in TODO.md §2.4. Once the SDK produces an id_token,
    /// pass it to `exchangeIdToken(provider: .google, ...)` and delete
    /// the simulated round-trip below.
    func signInWithGoogle() async throws -> User {
        try await Task.sleep(nanoseconds: 700_000_000)
        return await mintMockSession(provider: .google, subject: UUID().uuidString, name: nil)
    }

    /// POST the OAuth id_token to the Worker's /v1/auth/session. On
    /// success stores the returned sessionJwt in the shared APIClient.
    /// On failure falls back to a local mock so the app keeps working
    /// even when the backend is unreachable.
    private func exchangeIdToken(
        provider: AuthProvider,
        idToken: String,
        displayName: String?,
        fallbackSubject: String
    ) async -> User {
        do {
            let resp = try await APIClient.shared.exchange(
                provider: provider, idToken: idToken, displayName: displayName
            )
            // Store session so subsequent API calls carry Authorization.
            APIClient.shared.sessionToken = resp.sessionJwt
            APIClient.shared.demoAthleteId = nil
            return User(
                id: resp.suiAddress,
                displayName: resp.displayName,
                avatarURL: nil,
                goal: nil,
                suiAddress: resp.suiAddress,
                suinsName: resp.suinsName,
                suggestedHandle: resp.handle,
                createdAt: .now
            )
        } catch {
            // Network / backend unavailable — keep the user on-boarded
            // with a stable mock address so they can still use the app.
            return await mintMockSession(
                provider: provider, subject: fallbackSubject, name: displayName
            )
        }
    }

    // MARK: - Private

    private func requestAppleCredential() async throws -> ASAuthorizationAppleIDCredential {
        try await withCheckedThrowingContinuation { cont in
            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            request.requestedScopes = [.fullName]

            let controller = ASAuthorizationController(authorizationRequests: [request])
            let delegate = AppleAuthDelegate(continuation: cont)
            controller.delegate = delegate
            controller.presentationContextProvider = delegate
            // Keep delegate alive until completion
            objc_setAssociatedObject(controller, &AppleAuthDelegateKey, delegate, .OBJC_ASSOCIATION_RETAIN)
            controller.performRequests()
        }
    }

    private static func displayName(from credential: ASAuthorizationAppleIDCredential) -> String? {
        if let full = credential.fullName {
            let parts = [full.givenName, full.familyName].compactMap { $0 }
            let joined = parts.joined(separator: " ")
            if !joined.isEmpty { return joined }
        }
        return nil
    }

    /// Simulate the backend exchange. Produces a deterministic-looking Sui address
    /// derived from the OAuth subject so the same login returns the same address
    /// across sessions — the crucial property zkLogin provides.
    private func mintMockSession(provider: AuthProvider, subject: String, name: String?) async -> User {
        try? await Task.sleep(nanoseconds: 900_000_000) // feel of a real round-trip
        let address = Self.mockSuiAddress(for: subject, provider: provider)
        let displayName = name ?? Self.defaultDisplayName(for: provider)
        let user = User(
            id: address,
            displayName: displayName,
            avatarURL: nil,
            goal: nil,
            suiAddress: address,
            createdAt: .now
        )
        return user
    }

    private static func mockSuiAddress(for subject: String, provider: AuthProvider) -> String {
        let seed = "\(provider.rawValue):\(subject)"
        let digest = SHA256.hash(data: Data(seed.utf8))
        return "0x" + digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func defaultDisplayName(for provider: AuthProvider) -> String {
        switch provider {
        case .apple: return "Athlete"
        case .google: return "Athlete"
        }
    }
}

// MARK: - Apple delegate

private var AppleAuthDelegateKey: UInt8 = 0

private final class AppleAuthDelegate: NSObject,
                                       ASAuthorizationControllerDelegate,
                                       ASAuthorizationControllerPresentationContextProviding {
    let continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>
    init(continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>) {
        self.continuation = continuation
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        if let cred = authorization.credential as? ASAuthorizationAppleIDCredential {
            continuation.resume(returning: cred)
        } else {
            continuation.resume(throwing: AuthService.AuthError.failed("unexpected credential"))
        }
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithError error: Error) {
        let ns = error as NSError
        if ns.domain == ASAuthorizationError.errorDomain,
           ns.code == ASAuthorizationError.canceled.rawValue {
            continuation.resume(throwing: AuthService.AuthError.cancelled)
        } else {
            continuation.resume(throwing: AuthService.AuthError.failed(error.localizedDescription))
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // There is always at least one foreground-active window scene when
        // an auth controller is presenting.
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        if let window = scene?.windows.first { return window }
        return ASPresentationAnchor(windowScene: scene!)
    }
}
