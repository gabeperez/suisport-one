import SwiftUI

/// Three-stat breakdown of the user's Sweat economy. Surfaced from
/// the green "Lifetime Sweat earned" hero card on the feed.
///
/// Conceptually:
///   • **Lifetime earned** — every Sweat ever credited to the user
///     across all workouts. Includes unclaimed sessions still sitting
///     in HealthKit.
///   • **Ready to redeem** — current balance on Sui. What the user can
///     actually spend right now in Rewards.
///   • **Redeemed** — best-effort estimate of Sweat already spent,
///     derived from `lifetime minted on chain − current wallet`. Not
///     a perfect ledger but accurate enough to make the breakdown
///     legible without a server-side spend tracker.
struct SweatBreakdownSheet: View {
    /// True lifetime credited (sum of `pointsMinted` on every server
    /// mint, including bonuses). Comes from the local SweatLedger.
    let lifetimeCredited: Int
    /// On-chain wallet balance display string from the server
    /// (`SweatBalanceResponse.display`).
    let inWalletDisplay: String?
    /// Numeric parse of inWalletDisplay for math (best-effort,
    /// truncates fractional Sweat).
    let inWalletEstimate: Int
    /// Sum of points across workouts that landed on chain — the raw
    /// "what your workouts paid" figure, before bonuses.
    let lifetimeOnChain: Int
    /// True lifetime spent (sum of `costPoints` on every successful
    /// redemption). Comes from the local SweatLedger.
    let totalRedeemed: Int
    let onClose: () -> Void
    let onRedeem: (() -> Void)?

    /// Bonus = ledger-credited exceeds raw workout total. Captures
    /// every extra Sweat the server reward formula stacked on top of
    /// the user's straight-line points (first-time mint, streaks,
    /// multipliers).
    private var bonusEarned: Int {
        max(0, lifetimeCredited - lifetimeOnChain)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            header
            statBlock(
                label: "Lifetime earned",
                value: lifetimeCredited.formatted(),
                caption: "Every Sweat the chain has ever credited to your wallet.",
                icon: "bolt.heart.fill",
                tint: Theme.Color.accent,
                ink: Theme.Color.accentInk
            )
            statBlock(
                label: "Ready to redeem",
                value: inWalletDisplay ?? "0",
                caption: "Current balance on Sui — yours to spend in Rewards.",
                icon: "wallet.pass.fill",
                tint: Theme.Color.sky.opacity(0.18),
                ink: Theme.Color.sky
            )
            // With a real ledger, bonus and redeemed can both be
            // non-zero. Show bonus when there is one (it's the more
            // exciting story); fall through to redeemed otherwise.
            if bonusEarned > 0 {
                statBlock(
                    label: "Bonus earned",
                    value: "+\(bonusEarned.formatted())",
                    caption: "First-time mint, streaks, and multipliers stacked extra Sweat on top.",
                    icon: "sparkles",
                    tint: Theme.Color.gold.opacity(0.18),
                    ink: Theme.Color.gold
                )
            }
            if totalRedeemed > 0 || bonusEarned == 0 {
                statBlock(
                    label: "Already redeemed",
                    value: totalRedeemed.formatted(),
                    caption: "Sweat you've cashed in for tickets, drops, and gear.",
                    icon: "ticket.fill",
                    tint: Theme.Color.bgElevated,
                    ink: Theme.Color.inkSoft
                )
            }
            Spacer(minLength: 0)
            if let onRedeem {
                PrimaryButton(
                    title: "Redeem Sweat",
                    icon: "arrow.up.right",
                    tint: Theme.Color.ink,
                    fg: Theme.Color.inkInverse
                ) {
                    onRedeem()
                }
            }
        }
        .padding(Theme.Space.lg)
        .background(Theme.Color.bg.ignoresSafeArea())
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your Sweat")
                    .font(.displayS)
                    .foregroundStyle(Theme.Color.ink)
                Text("How your earnings break down — soulbound trophy on Sui, redeemable Sweat in your wallet.")
                    .font(.bodyS)
                    .foregroundStyle(Theme.Color.inkSoft)
            }
            Spacer()
            Button {
                Haptics.tap()
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.Color.inkSoft)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Theme.Color.bgElevated))
            }
            .buttonStyle(.plain)
        }
    }

    private func statBlock(
        label: String,
        value: String,
        caption: String,
        icon: String,
        tint: Color,
        ink: Color
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tint)
                    .frame(width: 52, height: 52)
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(ink)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .tracking(0.04)
                    .foregroundStyle(Theme.Color.inkSoft)
                Text(value)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Color.ink)
                    .contentTransition(.numericText())
                    .monospacedDigit()
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Color.inkFaint)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .fill(Theme.Color.bgElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                        .strokeBorder(Theme.Color.stroke, lineWidth: 1)
                )
        )
    }
}
