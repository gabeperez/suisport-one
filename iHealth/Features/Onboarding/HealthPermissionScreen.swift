import SwiftUI

struct HealthPermissionScreen: View {
    @Environment(AppState.self) private var app
    @State private var requesting = false

    var body: some View {
        OnboardingShell(showsBack: true) {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                Spacer()
                icon
                headline
                bullets
                Spacer()
                Spacer()
            }
            .padding(.horizontal, Theme.Space.lg)
        } actions: {
            PrimaryButton(
                title: requesting ? "Checking…" : "Connect Apple Health",
                icon: requesting ? nil : "heart.fill",
                isLoading: requesting,
                tint: Theme.Color.hot,
                fg: .white
            ) {
                Task { await request() }
            }
            GhostButton(title: "Not now") {
                app.advanceOnboarding()
            }
        }
    }

    private var icon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Theme.Color.hot.opacity(0.12))
                .frame(width: 100, height: 100)
            Image(systemName: "heart.fill")
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(Theme.Color.hot)
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Your workouts.\nYour points.")
                .font(.displayL)
                .foregroundStyle(Theme.Color.ink)
                .lineSpacing(-4)
            Text("SuiSport ONE reads Apple Health to count your workouts.\nWe never see your data without your OK.")
                .font(.bodyL)
                .foregroundStyle(Theme.Color.inkSoft)
        }
    }

    private var bullets: some View {
        VStack(alignment: .leading, spacing: 14) {
            row("Counts runs, rides, walks, lifts, and more", "checkmark.circle.fill")
            row("You pick what to share — change anytime", "lock.fill")
            row("Stays encrypted and stays yours", "sparkles")
        }
        .padding(Theme.Space.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .fill(Theme.Color.bgElevated)
        )
    }

    private func row(_ text: String, _ icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.Color.accentDeep)
            Text(text)
                .font(.bodyM)
                .foregroundStyle(Theme.Color.ink)
            Spacer(minLength: 0)
        }
    }

    private func request() async {
        requesting = true
        defer { requesting = false }
        _ = await app.requestHealthAuth()
        Haptics.success()
        app.advanceOnboarding()
    }
}

#Preview {
    HealthPermissionScreen().environment(AppState())
}
