import SwiftUI
import UIKit
import AuthenticationServices

/// Coordinates a "sign a server challenge with your Sui wallet" flow.
///
/// There's no universal iOS protocol for "dapp talks to wallet app" on
/// Sui the way WalletConnect does on EVM chains. Each wallet app has
/// its own deep-link scheme and response format. So instead of
/// hard-coupling to a single wallet, this bridge presents a small
/// sheet that:
///   1. Fetches a fresh challenge from `/v1/auth/wallet/challenge`
///   2. Offers two paths to sign it:
///        a. "Open Slush" → deep-links to slush://, which is a
///           best-effort shortcut. Works for users with Slush installed.
///        b. "I'll sign elsewhere" → copies the nonce to the clipboard
///           for manual signing (any wallet, desktop Slush, etc.)
///   3. Accepts pasted-back `{address, signature}` as a JSON blob
///   4. Returns the signed triple to the caller
///
/// When Sui mobile wallets standardize a proper dapp-connect protocol
/// (WalletConnect v2 for Sui, Enoki Connect, etc.), this bridge gets
/// swapped for that without the rest of the auth plumbing changing.
@MainActor
final class WalletConnectBridge {
    static let shared = WalletConnectBridge()

    struct SignedChallenge {
        let challengeId: String
        let address: String
        let signature: String
    }

    /// Preferred path: open our hosted `/wallet-connect` page in an
    /// ephemeral browser (ASWebAuthenticationSession). The page runs
    /// the real Sui Wallet Standard flow and redirects back to
    /// `suisport://wallet-connect-callback?address=…&signature=…`. We
    /// intercept the callback and return the signed triple.
    ///
    /// Fallback path: when the user cancels the web session OR the
    /// page's JS link explicitly returns `?cancel=paste`, drop into
    /// the paste-back sheet so they always have a way through.
    func collectSignedChallenge() async throws -> SignedChallenge {
        let challenge = try await APIClient.shared.walletChallenge()

        if let signed = try? await webBridge(challenge: challenge) {
            return signed
        }
        // Web path cancelled or failed → manual paste-back sheet.
        return try await pasteBackSheet(challenge: challenge)
    }

    private func webBridge(
        challenge: WalletChallengeResponse
    ) async throws -> SignedChallenge {
        let scheme = "suisport"
        let callback: URL = try await withCheckedThrowingContinuation { cont in
            let session = ASWebAuthenticationSession(
                url: Self.bridgeURL(for: challenge), callbackURLScheme: scheme
            ) { url, err in
                if let err {
                    cont.resume(throwing: err)
                    return
                }
                guard let url else {
                    cont.resume(throwing: Cancelled())
                    return
                }
                cont.resume(returning: url)
            }
            session.presentationContextProvider = WebAuthAnchorProvider.shared
            session.start()
        }

        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
            .queryItems ?? []
        func q(_ name: String) -> String? {
            items.first(where: { $0.name == name })?.value
        }
        // The HTML explicitly asks for paste-back with cancel=paste —
        // raise a sentinel so the caller falls through.
        if q("cancel") == "paste" { throw Cancelled() }

        guard let address = q("address"), let signature = q("signature"),
              let id = q("challengeId")
        else { throw Cancelled() }

        return SignedChallenge(challengeId: id, address: address, signature: signature)
    }

    private func pasteBackSheet(
        challenge: WalletChallengeResponse
    ) async throws -> SignedChallenge {
        // Wait until the ASWebAuthenticationSession's container has
        // fully dismissed. Presenting straight after its completion
        // handler races the out-animation — the view is still tagged
        // as topMost but isn't in the window hierarchy, so present()
        // silently fails and the continuation leaks.
        for _ in 0..<20 {                       // up to ~1s
            if let vc = Self.topMost,
               vc.isBeingDismissed == false,
               vc.view.window != nil {
                break
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        return try await withCheckedThrowingContinuation { cont in
            // Belt-and-suspenders: capture the continuation into a
            // box so present()'s completion can resume it on failure.
            let box = ContinuationBox(cont)
            let host = UIHostingController(rootView: WalletConnectSheet(
                challenge: challenge,
                onCompleted: { signed in box.resume(.success(signed)) },
                onCancel: { box.resume(.failure(Cancelled())) },
                challengeURL: Self.bridgeURL(for: challenge)
            ))
            host.modalPresentationStyle = .formSheet

            guard let presenter = Self.topMost, presenter.view.window != nil else {
                box.resume(.failure(Cancelled()))
                return
            }
            presenter.present(host, animated: true) { [weak host] in
                if host?.view.window == nil {
                    // Present silently no-op'd (edge case).
                    box.resume(.failure(Cancelled()))
                }
            }
        }
    }

    /// Public URL of the hosted bridge page for a given challenge.
    /// Served as a Cloudflare Pages static app (Vite + React +
    /// @mysten/dapp-kit's ConnectButton + useSignPersonalMessage).
    /// Used both by the ASWebAuthenticationSession path AND the
    /// "Open in Safari" escape hatch on the paste-back sheet.
    static func bridgeURL(for challenge: WalletChallengeResponse) -> URL {
        var comps = URLComponents(string:
            "https://suisport-wallet.pages.dev/")!
        comps.queryItems = [
            URLQueryItem(name: "challengeId", value: challenge.challengeId),
            URLQueryItem(name: "nonce", value: challenge.nonce),
            URLQueryItem(name: "returnScheme", value: "suisport"),
        ]
        return comps.url!
    }

    struct Cancelled: Error {}

    /// Guards against double-resume + silent drop of a checked
    /// continuation. Both success and failure paths go through
    /// `resume(_:)`; subsequent calls are ignored.
    private final class ContinuationBox {
        private var cont: CheckedContinuation<SignedChallenge, Error>?
        init(_ c: CheckedContinuation<SignedChallenge, Error>) { self.cont = c }
        func resume(_ result: Result<SignedChallenge, Error>) {
            guard let c = cont else { return }
            cont = nil
            switch result {
            case .success(let v): c.resume(returning: v)
            case .failure(let e): c.resume(throwing: e)
            }
        }
    }

    private static var topMost: UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var vc = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let presented = vc?.presentedViewController { vc = presented }
        return vc
    }
}

/// Presentation anchor for ASWebAuthenticationSession. Re-used from
/// GoogleAuth's pattern — grab the first foreground-active window.
private final class WebAuthAnchorProvider: NSObject,
    ASWebAuthenticationPresentationContextProviding {
    static let shared = WebAuthAnchorProvider()
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

/// Paste-back sheet. This is the fallback when the hosted web
/// bridge's ASWebAuthenticationSession doesn't give us a signed
/// result (user cancels, no wallet installed, etc.). Designed to
/// feel intentional — numbered step cards, Sui-blue accents,
/// collapsible advanced affordance — not debugger-ish.
struct WalletConnectSheet: View {
    let challenge: WalletChallengeResponse
    let onCompleted: (WalletConnectBridge.SignedChallenge) -> Void
    let onCancel: () -> Void
    /// Hosted bridge URL for the "Open in Safari" / "Try Slush app"
    /// escape hatches. Set by the presenter; nil means both buttons
    /// are hidden.
    var challengeURL: URL? = nil

    @State private var address = ""
    @State private var signature = ""
    @State private var pastedBlob = ""
    @State private var copied = false
    @State private var showAdvanced = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private let suiBlue = Color(red: 0.13, green: 0.45, blue: 0.86)
    private let suiBlueSoft = Color(red: 0.13, green: 0.45, blue: 0.86).opacity(0.12)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Space.md) {
                    hero
                    if challengeURL != nil { quickActions }
                    step1Card
                    step2Card
                    advancedCard
                    Color.clear.frame(height: 40)
                }
                .padding(Theme.Space.lg)
            }
            .background(Theme.Color.bg.ignoresSafeArea())
            .navigationTitle("Connect wallet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onCancel(); dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        submit()
                    } label: {
                        Text("Sign in")
                            .fontWeight(.semibold)
                    }
                    .disabled(!canSubmit)
                }
            }
        }
    }

    private var canSubmit: Bool {
        address.hasPrefix("0x") && address.count == 66 && !signature.isEmpty
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(suiBlueSoft).frame(width: 72, height: 72)
                Image(systemName: "wallet.pass.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(suiBlue)
            }
            Text("Connect your Sui wallet")
                .font(.titleL).foregroundStyle(Theme.Color.ink)
            Text("Your wallet signs a one-time nonce — your private keys never leave it.")
                .font(.bodyM)
                .foregroundStyle(Theme.Color.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Space.md)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Space.md)
    }

    // MARK: - Quick actions
    //
    // Two top-of-sheet affordances that try to reach a real signing
    // surface without the user having to copy/paste:
    //   1. Open in Safari → full UIApplication.open of the hosted
    //      bridge URL. Mobile Safari can see installed wallet
    //      extensions + Slush's universal link, so detection works
    //      in contexts the ephemeral ASWebAuthenticationSession
    //      blocks. Safari redirects back to `suisport://…` when the
    //      wallet returns a signature, which re-enters this app.
    //   2. Open Slush app → attempt the Slush mobile universal link.
    //      If Slush is installed, iOS switches apps + surfaces a
    //      sign prompt. If not, the URL silently falls back to a
    //      web page.
    //
    // Both skip the paste-back entirely when successful.
    private var quickActions: some View {
        VStack(spacing: 10) {
            if let url = challengeURL {
                Button {
                    Haptics.tap()
                    openURL(url)    // mobile Safari
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "safari.fill")
                            .font(.system(size: 15, weight: .bold))
                        Text("Open in Safari")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(Capsule().fill(suiBlue))
                }
                .buttonStyle(.plain)
            }
            Button {
                Haptics.tap()
                let msg = challenge.nonce.data(using: .utf8)?
                    .base64EncodedString()
                    .replacingOccurrences(of: "+", with: "-")
                    .replacingOccurrences(of: "/", with: "_")
                    .replacingOccurrences(of: "=", with: "") ?? ""
                // Best-effort deep link to Slush's native app. If
                // installed, it handles the message and returns via
                // universal link; if not, iOS silently no-ops.
                if let url = URL(string: "https://slush.app/sign?message=\(msg)&return=suisport%3A%2F%2Fwallet-connect-callback") {
                    openURL(url)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.right.circle.fill")
                        .font(.system(size: 15, weight: .bold))
                    Text("Try Slush app")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Spacer()
                }
                .foregroundStyle(Theme.Color.ink)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(Capsule().fill(Theme.Color.bgElevated))
                .overlay(Capsule().strokeBorder(Theme.Color.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
            Text("Or copy the nonce below and sign in any Sui wallet — paste the result back when done.")
                .font(.caption)
                .foregroundStyle(Theme.Color.inkFaint)
                .multilineTextAlignment(.center)
                .padding(.top, 2)
        }
    }

    // MARK: - Step cards

    private var step1Card: some View {
        stepCard(number: 1, title: "Copy the sign-in message") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "signature")
                        .foregroundStyle(suiBlue)
                    Text(challenge.nonce)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Theme.Color.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .fill(Theme.Color.bg))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .strokeBorder(Theme.Color.stroke, lineWidth: 1)
                )

                Button {
                    UIPasteboard.general.string = challenge.nonce
                    Haptics.success()
                    withAnimation(Theme.Motion.snap) { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation(Theme.Motion.snap) { copied = false }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc.fill")
                        Text(copied ? "Copied" : "Copy message")
                    }
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(Capsule().fill(suiBlue))
                }
                .buttonStyle(.plain)

                Text("Open Slush (or any Sui wallet) → Settings → Sign Personal Message → paste.")
                    .font(.caption)
                    .foregroundStyle(Theme.Color.inkFaint)
            }
        }
    }

    private var step2Card: some View {
        stepCard(number: 2, title: "Paste the signed result") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("""
                { "address": "0x…", "signature": "…" }
                """, text: $pastedBlob, axis: .vertical)
                    .font(.system(.footnote, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .lineLimit(3...6)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .fill(Theme.Color.bg))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.md)
                            .strokeBorder(canSubmit ? suiBlue : Theme.Color.stroke,
                                          lineWidth: canSubmit ? 1.5 : 1)
                    )
                    .onChange(of: pastedBlob) { _, new in tryParse(new) }
                if canSubmit {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Ready to sign in")
                    }
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.Color.accentDeep)
                } else {
                    Text("Your wallet returns a JSON object — we'll parse the address and signature automatically.")
                        .font(.caption).foregroundStyle(Theme.Color.inkFaint)
                }
            }
        }
    }

    @ViewBuilder
    private var advancedCard: some View {
        DisclosureGroup(isExpanded: $showAdvanced) {
            VStack(alignment: .leading, spacing: 10) {
                advField(label: "Sui address", placeholder: "0x…", text: $address)
                advField(label: "Signature", placeholder: "AA…", text: $signature, multiline: true)
            }
            .padding(.top, 10)
        } label: {
            HStack {
                Image(systemName: "wrench.and.screwdriver")
                    .foregroundStyle(Theme.Color.inkSoft)
                Text("Paste fields individually")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
            }
            .foregroundStyle(Theme.Color.inkSoft)
        }
        .padding(Theme.Space.md)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.lg)
            .fill(Theme.Color.bgElevated))
    }

    private func advField(label: String, placeholder: String, text: Binding<String>,
                          multiline: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.Color.inkSoft)
            if multiline {
                TextField(placeholder, text: text, axis: .vertical)
                    .font(.system(.footnote, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .lineLimit(2...5)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .fill(Theme.Color.bg))
            } else {
                TextField(placeholder, text: text)
                    .font(.system(.footnote, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .fill(Theme.Color.bg))
            }
        }
    }

    // MARK: - Shell

    private func stepCard<Content: View>(
        number: Int, title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(suiBlue)
                        .frame(width: 24, height: 24)
                    Text("\(number)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.Color.ink)
                Spacer()
            }
            content()
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.lg)
            .fill(Theme.Color.bgElevated))
    }

    private func tryParse(_ s: String) {
        guard let data = s.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        if let a = obj["address"] as? String { address = a }
        if let sig = obj["signature"] as? String { signature = sig }
    }

    private func submit() {
        onCompleted(.init(
            challengeId: challenge.challengeId,
            address: address.trimmingCharacters(in: .whitespacesAndNewlines),
            signature: signature.trimmingCharacters(in: .whitespacesAndNewlines)
        ))
        dismiss()
    }
}
