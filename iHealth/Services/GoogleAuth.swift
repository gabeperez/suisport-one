import Foundation
import AuthenticationServices
import CryptoKit

/// Real Google OAuth 2.0 + PKCE flow for iOS. No SDK dependency — we use
/// `ASWebAuthenticationSession` for the auth step (ephemeral, no
/// Info.plist URL-scheme registration needed) and URLSession for the
/// token exchange.
///
/// After signIn() returns, the id_token is ready to hand to the SuiSport
/// backend's `/v1/auth/session` which passes it to Enoki's zkLogin
/// derivation — same path Apple uses.
///
/// Configuration: set `GoogleAuth.clientId` to your iOS OAuth client id
/// from https://console.cloud.google.com/apis/credentials. Bundle id in
/// that Google Cloud config MUST be `gimme.coffee.iHealth`.
enum GoogleAuth {

    /// Fill this in with your Google iOS OAuth client id.
    /// Shape: `XXXXX-YYYYY.apps.googleusercontent.com`.
    static let clientId: String = ""    // TODO: paste your Google client id

    static var isConfigured: Bool { !clientId.isEmpty }

    /// Kick off the full PKCE flow. Throws on cancel / network / API
    /// errors. Returns the Google-signed id_token (a JWT) on success.
    @MainActor
    static func signIn() async throws -> String {
        guard isConfigured else { throw GoogleAuthError.notConfigured }

        let verifier = randomPKCEVerifier()
        let challenge = pkceChallenge(verifier)
        let nonce = randomNonce()
        let redirect = "\(reverseScheme):/oauth2redirect"

        var comps = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "nonce", value: nonce),
        ]

        let callback = try await startWebAuthSession(url: comps.url!, scheme: reverseScheme)
        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value
        else {
            throw GoogleAuthError.badCallback
        }
        return try await exchangeCodeForIdToken(code: code, verifier: verifier, redirect: redirect)
    }

    // MARK: - Internals

    /// Reverse of the DNS-reversed part before `.apps.googleusercontent.com`
    /// — Google's prescribed URL scheme for mobile OAuth.
    private static var reverseScheme: String {
        // "XYZ.apps.googleusercontent.com" → "com.googleusercontent.apps.XYZ"
        let parts = clientId.split(separator: ".")
        guard let first = parts.first else { return "" }
        return "com.googleusercontent.apps.\(first)"
    }

    @MainActor
    private static func startWebAuthSession(url: URL, scheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            let session = ASWebAuthenticationSession(
                url: url, callbackURLScheme: scheme
            ) { cb, err in
                if let err {
                    let ns = err as NSError
                    if ns.domain == ASWebAuthenticationSessionError.errorDomain,
                       ns.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        cont.resume(throwing: GoogleAuthError.cancelled)
                    } else {
                        cont.resume(throwing: GoogleAuthError.session(err.localizedDescription))
                    }
                    return
                }
                guard let cb else {
                    cont.resume(throwing: GoogleAuthError.badCallback)
                    return
                }
                cont.resume(returning: cb)
            }
            session.presentationContextProvider = PresentationContextProvider.shared
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }

    private static func exchangeCodeForIdToken(
        code: String, verifier: String, redirect: String
    ) async throws -> String {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "client_id": clientId,
            "code": code,
            "code_verifier": verifier,
            "redirect_uri": redirect,
            "grant_type": "authorization_code",
        ]
        req.httpBody = body.map { key, value in
            "\(key)=\(urlEncode(value))"
        }.joined(separator: "&").data(using: .utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw GoogleAuthError.tokenExchange(msg)
        }
        let decoded = try JSONDecoder().decode(GoogleTokenResponse.self, from: data)
        return decoded.idToken
    }

    // MARK: PKCE helpers

    private static func randomPKCEVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, 32, &bytes)
        return base64URL(Data(bytes))
    }

    private static func pkceChallenge(_ verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URL(Data(digest))
    }

    private static func randomNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, 16, &bytes)
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func urlEncode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }
}

enum GoogleAuthError: Error {
    case notConfigured
    case cancelled
    case badCallback
    case session(String)
    case tokenExchange(String)
}

private struct GoogleTokenResponse: Decodable {
    let idToken: String
    let accessToken: String?
    let expiresIn: Int?
    let tokenType: String?
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case scope
    }
}

/// ASWebAuthenticationSession needs a presentation anchor; grab the
/// first foreground-active window.
private final class PresentationContextProvider: NSObject,
    ASWebAuthenticationPresentationContextProviding {
    static let shared = PresentationContextProvider()
    func presentationAnchor(
        for session: ASWebAuthenticationSession
    ) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        if let window = scene?.windows.first { return window }
        return ASPresentationAnchor(windowScene: scene!)
    }
}
