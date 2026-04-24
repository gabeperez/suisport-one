import SwiftUI
import UIKit

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

    /// Presents the sheet and suspends until the user completes or
    /// cancels. Throws `Cancelled` on explicit cancel.
    func collectSignedChallenge() async throws -> SignedChallenge {
        let challenge = try await APIClient.shared.walletChallenge()
        return try await withCheckedThrowingContinuation { cont in
            let host = UIHostingController(rootView: WalletConnectSheet(
                challenge: challenge,
                onCompleted: { signed in cont.resume(returning: signed) },
                onCancel: { cont.resume(throwing: Cancelled()) }
            ))
            host.modalPresentationStyle = .formSheet
            Self.topMost?.present(host, animated: true)
        }
    }

    struct Cancelled: Error {}

    private static var topMost: UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var vc = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let presented = vc?.presentedViewController { vc = presented }
        return vc
    }
}

/// Sheet UI. Small, focused, nothing fancy — this is a beta surface
/// that'll get replaced when the Sui wallet-connect story stabilizes.
struct WalletConnectSheet: View {
    let challenge: WalletChallengeResponse
    let onCompleted: (WalletConnectBridge.SignedChallenge) -> Void
    let onCancel: () -> Void

    @State private var address = ""
    @State private var signature = ""
    @State private var errorMessage: String?
    @State private var pastedBlob = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    header
                    step1
                    step2
                    errorBlock
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
                    Button("Done") {
                        submit()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSubmit)
                }
            }
        }
    }

    private var canSubmit: Bool {
        address.hasPrefix("0x") && address.count == 66 && !signature.isEmpty
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sign in with your existing Sui wallet")
                .font(.titleM).foregroundStyle(Theme.Color.ink)
            Text("Your wallet proves it's you by signing a one-time nonce. We verify the signature on the server — no private keys leave your wallet.")
                .font(.bodyM).foregroundStyle(Theme.Color.inkSoft)
        }
    }

    private var step1: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("1. Sign this message in your wallet", systemImage: "signature")
                .font(.labelBold).foregroundStyle(Theme.Color.ink)
            Text(challenge.nonce)
                .font(.labelMono)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .fill(Theme.Color.bgElevated))
            HStack(spacing: 10) {
                Button {
                    UIPasteboard.general.string = challenge.nonce
                    Haptics.success()
                } label: {
                    Label("Copy nonce", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    // Best-effort deep link to Slush. If it's not
                    // installed, iOS just does nothing — user falls back
                    // to copy-paste.
                    let msg = challenge.nonce.data(using: .utf8)?
                        .base64EncodedString() ?? ""
                    if let url = URL(string: "slush://sign-personal-message?message=\(msg)") {
                        UIApplication.shared.open(url, options: [:]) { opened in
                            if !opened { Haptics.error() }
                        }
                    }
                } label: {
                    Label("Open Slush", systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var step2: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("2. Paste the signed result", systemImage: "square.and.arrow.down")
                .font(.labelBold).foregroundStyle(Theme.Color.ink)
            Text("Your wallet returns a JSON like `{\"address\": \"0x…\", \"signature\": \"…\"}`. Paste it below — we'll fill in the fields automatically.")
                .font(.caption).foregroundStyle(Theme.Color.inkSoft)

            TextField("Paste JSON here", text: $pastedBlob, axis: .vertical)
                .font(.labelMono)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .lineLimit(3...6)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .fill(Theme.Color.surface))
                .onChange(of: pastedBlob) { _, new in tryParse(new) }

            // Advanced: lets the user enter address + signature individually
            // if their wallet doesn't return a nice JSON blob.
            VStack(alignment: .leading, spacing: 6) {
                TextField("Address (0x…)", text: $address)
                    .font(.labelMono).textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Signature", text: $signature, axis: .vertical)
                    .font(.labelMono).textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .lineLimit(2...5)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.md)
                .fill(Theme.Color.surface))
        }
    }

    @ViewBuilder
    private var errorBlock: some View {
        if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Color.hot)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .fill(Theme.Color.hot.opacity(0.12)))
        }
    }

    private func tryParse(_ s: String) {
        // Accept either a JSON blob or raw "address,signature" form.
        guard let data = s.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        if let a = obj["address"] as? String { address = a }
        if let sig = obj["signature"] as? String { signature = sig }
    }

    private func submit() {
        errorMessage = nil
        onCompleted(.init(
            challengeId: challenge.challengeId,
            address: address.trimmingCharacters(in: .whitespacesAndNewlines),
            signature: signature.trimmingCharacters(in: .whitespacesAndNewlines)
        ))
        dismiss()
    }
}
