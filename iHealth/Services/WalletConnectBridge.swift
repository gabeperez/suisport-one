import SwiftUI
import UIKit

/// Coordinates a "sign a server challenge with your Sui wallet" flow.
///
/// Canonical flow — the Slush universal link:
///
///   1. POST /v1/auth/wallet/challenge → { challengeId, nonce }
///   2. UIApplication.open(
///        https://my.slush.app/browse/<our dapp-kit page>
///      )
///      — iOS routes the universal link to Slush if installed,
///        otherwise to Slush web in Safari. Slush loads our URL in
///        its in-app browser; Slush is auto-injected into the page
///        via the Wallet Standard. Our dapp-kit ConnectButton +
///        useSignPersonalMessage then run without any context
///        switching — signing is in-wallet.
///   3. When the user signs, our page redirects to
///        suisport://wallet-connect-callback?challengeId=…&
///                 address=…&signature=…
///      iOS routes that URL back to SuiSport (CFBundleURLTypes
///      registers the scheme in Info.plist).
///   4. AppState.handleIncomingURL parses the params and resumes
///      the pending continuation held by WalletConnectBridge.
///
/// Fallback — manual paste-back: if the universal link takes longer
/// than 2 minutes to return, we surface a sheet with the nonce +
/// paste fields so the user can sign in any wallet they have.
@MainActor
final class WalletConnectBridge {
    static let shared = WalletConnectBridge()

    struct SignedChallenge {
        let challengeId: String
        let address: String
        let signature: String
    }

    private var pending: PendingAuth?
    private struct PendingAuth {
        let challengeId: String
        let continuation: CheckedContinuation<SignedChallenge, Error>
        let fallbackTimer: Task<Void, Never>?
    }

    /// Kicks off the full flow: challenge → deep link → waits for the
    /// `suisport://` callback. Throws `Cancelled` if the user backs out
    /// OR if we hit the fallback timeout.
    ///
    /// `useOtherWallet = false` (default) routes through Slush's
    /// `my.slush.app/browse/<url>` universal link — the best UX if
    /// the user has (or is willing to use) Slush.
    ///
    /// `useOtherWallet = true` opens our bridge URL directly in Safari,
    /// where dapp-kit's `ConnectButton` enumerates whatever Sui wallets
    /// the browser has registered (Suiet, Nightly, etc. via Wallet
    /// Standard). Use this when the user has an existing non-Slush
    /// wallet they'd rather sign with.
    func collectSignedChallenge(useOtherWallet: Bool = false) async throws -> SignedChallenge {
        // If a previous sign-in is mid-flight, cancel it so we don't
        // leak the continuation.
        pending?.continuation.resume(throwing: Cancelled())
        pending?.fallbackTimer?.cancel()
        pending = nil

        let challenge = try await APIClient.shared.walletChallenge()

        return try await withCheckedThrowingContinuation { cont in
            // 2-minute timeout so the user doesn't stare at a spinner
            // forever if they never return from the wallet.
            let timer = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 120_000_000_000)
                // Task inherits @MainActor from the enclosing
                // @MainActor class — same-actor call, no await needed.
                self?.timeout(challengeId: challenge.challengeId)
            }
            pending = PendingAuth(
                challengeId: challenge.challengeId,
                continuation: cont,
                fallbackTimer: timer
            )
            let deepLink = useOtherWallet
                ? Self.bridgeURL(for: challenge)
                : Self.slushUniversalLink(for: challenge)
            UIApplication.shared.open(deepLink, options: [:]) { [weak self] ok in
                if !ok {
                    // The link failed to open (extremely rare — both
                    // https targets always resolve).
                    Task { @MainActor in
                        self?.resolve(
                            challengeId: challenge.challengeId,
                            result: .failure(Cancelled())
                        )
                    }
                }
            }
        }
    }

    /// Called from the SceneDelegate / RootView onOpenURL handler for
    /// any suisport:// URL. Returns true if the URL was handled.
    @discardableResult
    func handleIncomingURL(_ url: URL) -> Bool {
        guard url.scheme == "suisport",
              url.host == "wallet-connect-callback"
        else { return false }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems ?? []
        func q(_ name: String) -> String? {
            items.first(where: { $0.name == name })?.value
        }
        guard let challengeId = q("challengeId") else { return false }
        guard let pending, pending.challengeId == challengeId else { return false }

        if q("cancel") == "paste" {
            resolve(challengeId: challengeId, result: .failure(Cancelled()))
            return true
        }

        guard let address = q("address"), let signature = q("signature") else {
            resolve(challengeId: challengeId, result: .failure(Cancelled()))
            return true
        }
        resolve(challengeId: challengeId, result: .success(
            SignedChallenge(challengeId: challengeId, address: address, signature: signature)
        ))
        return true
    }

    private func resolve(
        challengeId: String,
        result: Result<SignedChallenge, Error>
    ) {
        guard let p = pending, p.challengeId == challengeId else { return }
        p.fallbackTimer?.cancel()
        pending = nil
        switch result {
        case .success(let v): p.continuation.resume(returning: v)
        case .failure(let e): p.continuation.resume(throwing: e)
        }
    }

    /// Caller-side cancel: when the user navigates away from the
    /// auth flow before Slush returns, resume the pending continuation
    /// with `Cancelled` so the awaiting Task in AppState completes
    /// and `isAuthInFlight` flips back to false. Without this, backing
    /// out of Slush leaves AuthScreen showing a stuck spinner forever.
    func cancelPending() {
        guard let p = pending else { return }
        p.fallbackTimer?.cancel()
        pending = nil
        p.continuation.resume(throwing: Cancelled())
    }

    private func timeout(challengeId: String) {
        resolve(challengeId: challengeId, result: .failure(Timeout()))
    }

    struct Cancelled: Error {}
    struct Timeout: Error {}

    // ---- URL helpers ----

    /// Universal link that opens Slush (mobile app if installed, web
    /// if not) on a "browse this URL" intent. Slush loads the inner
    /// URL in its in-app browser with the wallet auto-injected.
    /// Pattern documented at:
    ///   packages/docs/content/slush-wallet/deep-linking.mdx
    /// in MystenLabs/ts-sdks.
    static func slushUniversalLink(for challenge: WalletChallengeResponse) -> URL {
        let inner = bridgeURL(for: challenge).absoluteString
        let encoded = inner.addingPercentEncoding(
            withAllowedCharacters: .urlHostAllowed
        ) ?? inner
        // Slush's scheme is `/browse/<url>` (URL goes after the slash,
        // not as a query param).
        return URL(string: "https://my.slush.app/browse/\(encoded)")!
    }

    /// Public URL of the dapp-kit bridge page for a given challenge.
    /// Hosted as a Cloudflare Pages static app with WalletProvider +
    /// ConnectButton + useSignPersonalMessage.
    static func bridgeURL(for challenge: WalletChallengeResponse) -> URL {
        var comps = URLComponents(string: "https://suisport-wallet.pages.dev/")!
        comps.queryItems = [
            URLQueryItem(name: "challengeId", value: challenge.challengeId),
            URLQueryItem(name: "nonce", value: challenge.nonce),
            URLQueryItem(name: "returnScheme", value: "suisport"),
        ]
        return comps.url!
    }
}
