import SwiftUI

/// Confirmation sheet for spending Sweat to unlock a fighter's
/// community. Surfaces the cost + what the user gets, and asks for an
/// explicit confirmation before debiting the wallet.
struct CommunityUnlockSheet: View {
    let athlete: Athlete
    let community: FighterCommunity
    let onConfirm: () -> Void

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Theme.Space.lg) {
            grabber
            hero
            details
            Spacer(minLength: 0)
            actions
        }
        .padding(Theme.Space.lg)
        .background(Theme.Color.bg.ignoresSafeArea())
    }

    private var grabber: some View {
        Capsule().fill(Theme.Color.stroke)
            .frame(width: 40, height: 4)
            .frame(maxWidth: .infinity)
    }

    private var hero: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.Color.accent.opacity(0.18))
                    .frame(width: 96, height: 96)
                AthleteAvatar(athlete: athlete, size: 88, showsTierRing: false)
            }
            VStack(spacing: 4) {
                Text("Join \(athlete.displayName)'s community")
                    .font(.titleL)
                    .foregroundStyle(Theme.Color.ink)
                    .multilineTextAlignment(.center)
                Text("Posts, training tips, AMAs, fight-week behind-the-scenes — straight from \(athlete.displayName.split(separator: " ").first.map(String.init) ?? "the fighter").")
                    .font(.bodyS)
                    .foregroundStyle(Theme.Color.inkSoft)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var details: some View {
        VStack(spacing: 0) {
            row(label: "Cost", value: "\(community.unlockSweatCost) Sweat")
            Divider().background(Theme.Color.stroke)
            row(label: "Your balance",
                value: "\(app.sweatPoints.total)",
                hint: "before this unlock")
            Divider().background(Theme.Color.stroke)
            row(label: "After unlock",
                value: "\(max(0, app.sweatPoints.total - community.unlockSweatCost))",
                hint: "remaining Sweat")
        }
        .padding(Theme.Space.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Theme.Color.bgElevated)
        )
    }

    private func row(label: String, value: String, hint: String? = nil) -> some View {
        HStack {
            Text(label)
                .font(.labelBold)
                .foregroundStyle(Theme.Color.inkSoft)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Color.ink)
                if let hint {
                    Text(hint)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Color.inkFaint)
                }
            }
        }
        .padding(.vertical, 10)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            PrimaryButton(
                title: "Spend \(community.unlockSweatCost) Sweat",
                icon: "bolt.heart.fill",
                tint: Theme.Color.accent,
                fg: Theme.Color.accentInk
            ) {
                onConfirm()
                dismiss()
            }
            Button("Not now") { dismiss() }
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.Color.inkSoft)
        }
    }
}
