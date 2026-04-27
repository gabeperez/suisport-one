import SwiftUI

/// Receipt for a freshly-minted workout. Drives the success sheet that
/// appears after `submitWorkout` returns — the demo's headline moment
/// where Sweat lands in the user's wallet on Sui and we hand them the
/// real Suiscan + Walrus links to prove it.
struct MintReceipt: Identifiable, Equatable {
    let id: UUID
    let pointsMinted: Int
    let txDigest: String
    let walrusBlobId: String?
    let workoutTitle: String

    init(
        id: UUID = UUID(),
        pointsMinted: Int,
        txDigest: String,
        walrusBlobId: String?,
        workoutTitle: String
    ) {
        self.id = id
        self.pointsMinted = pointsMinted
        self.txDigest = txDigest
        self.walrusBlobId = walrusBlobId
        self.workoutTitle = workoutTitle
    }

    /// The Sui explorer URL for this mint. Hardcoded to testnet here
    /// since the contract is testnet-only for the hackathon. Mainnet
    /// build will swap this via env later.
    var suiscanURL: URL {
        URL(string: "https://suiscan.xyz/testnet/tx/\(txDigest)")!
    }

    /// Walrus aggregator URL for the canonical workout JSON. Nil when
    /// upload was skipped or the pipeline ran in stub mode.
    var walruscanURL: URL? {
        guard let blobId = walrusBlobId else { return nil }
        return URL(string: "https://aggregator.walrus-testnet.walrus.space/v1/blobs/\(blobId)")
    }
}

/// Success sheet shown after a workout submit returns from the worker.
/// The +X count animates from 0 on appear so the user sees the Sweat
/// land. Suiscan + Walrus tap targets are real links — judges and users
/// can both verify the mint is on chain.
struct MintSuccessSheet: View {
    let receipt: MintReceipt
    let onDone: () -> Void

    @State private var displayedPoints: Int = 0
    @State private var sparkle = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            grabber
            sparkleHeader

            VStack(alignment: .leading, spacing: 8) {
                Text("+\(displayedPoints) Sweat")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Color.ink)
                    .contentTransition(.numericText())
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Earned")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.Color.inkSoft)
            }

            workoutRow

            VStack(spacing: 10) {
                explorerLink(
                    title: "View proof on Sui",
                    subtitle: shortDigest(receipt.txDigest),
                    icon: "checkmark.seal.fill",
                    url: receipt.suiscanURL
                )
                if let walrus = receipt.walruscanURL {
                    explorerLink(
                        title: "Permanent record",
                        subtitle: "tamper-proof workout data",
                        icon: "shippingbox.fill",
                        url: walrus
                    )
                }
            }

            disclaimer

            Spacer(minLength: 0)

            PrimaryButton(
                title: "Done",
                tint: Theme.Color.ink,
                fg: Theme.Color.inkInverse
            ) {
                Haptics.tap()
                onDone()
            }
        }
        .padding(Theme.Space.lg)
        .background(Theme.Color.bg.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationCornerRadius(Theme.Radius.xl)
        .onAppear {
            Haptics.success()
            withAnimation(.easeOut(duration: 1.2)) {
                displayedPoints = receipt.pointsMinted
            }
            withAnimation(.easeInOut(duration: 1.4).repeatCount(3, autoreverses: true)) {
                sparkle.toggle()
            }
        }
    }

    private var grabber: some View {
        Capsule().fill(Theme.Color.stroke)
            .frame(width: 40, height: 4)
            .frame(maxWidth: .infinity)
    }

    private var sparkleHeader: some View {
        ZStack {
            Circle()
                .fill(Theme.Color.accent.opacity(0.18))
                .frame(width: 96, height: 96)
            Image(systemName: "sparkles")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Theme.Color.accentDeep)
                .scaleEffect(sparkle ? 1.08 : 1.0)
        }
        .frame(maxWidth: .infinity)
    }

    private var workoutRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.Color.accentDeep)
            Text(receipt.workoutTitle)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.Color.ink)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Theme.Color.accent.opacity(0.10))
        )
    }

    private func explorerLink(
        title: String,
        subtitle: String,
        icon: String,
        url: URL
    ) -> some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Color.accentDeep)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Theme.Color.accent.opacity(0.18)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.Color.ink)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.Color.inkSoft)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Color.inkFaint)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(Theme.Color.bgElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                            .strokeBorder(Theme.Color.stroke, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var disclaimer: some View {
        Text("Your Sweat is safe and verifiable. Tap above to see the receipt.")
            .font(.system(size: 12))
            .foregroundStyle(Theme.Color.inkFaint)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func shortDigest(_ d: String) -> String {
        guard d.count > 16 else { return d }
        let prefix = d.prefix(8)
        let suffix = d.suffix(6)
        return "\(prefix)…\(suffix)"
    }
}

#Preview {
    Color.black.sheet(isPresented: .constant(true)) {
        MintSuccessSheet(
            receipt: MintReceipt(
                pointsMinted: 252,
                txDigest: "FYusVDGWTqpR3Twhj1hMqLBen9UikqR2BAWDmVKAvhmK",
                walrusBlobId: "0xbeefcafe…",
                workoutTitle: "Morning striking"
            ),
            onDone: {}
        )
    }
}
