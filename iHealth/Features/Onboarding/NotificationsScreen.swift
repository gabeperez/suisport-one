import SwiftUI
import UserNotifications

struct NotificationsScreen: View {
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
                title: requesting ? "Just a sec…" : "Turn on notifications",
                icon: requesting ? nil : "bell.badge.fill",
                isLoading: requesting,
                tint: Theme.Color.ink,
                fg: Theme.Color.inkInverse
            ) {
                Task { await request() }
            }
            GhostButton(title: "Maybe later") {
                app.completeOnboarding()
            }
        }
    }

    private var icon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Theme.Color.violet.opacity(0.15))
                .frame(width: 100, height: 100)
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(Theme.Color.violet)
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Don't miss a beat.")
                .font(.displayL)
                .foregroundStyle(Theme.Color.ink)
            Text("We'll only ping you when it matters.")
                .font(.bodyL)
                .foregroundStyle(Theme.Color.inkSoft)
        }
    }

    private var bullets: some View {
        VStack(alignment: .leading, spacing: 12) {
            row("Streak about to break", "flame.fill", tint: Theme.Color.hot)
            row("New sponsor quests you qualify for", "target", tint: Theme.Color.sky)
            row("Friends challenging you", "person.2.fill", tint: Theme.Color.violet)
        }
        .padding(Theme.Space.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .fill(Theme.Color.bgElevated)
        )
    }

    private func row(_ text: String, _ icon: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(Circle().fill(tint.opacity(0.15)))
            Text(text)
                .font(.bodyM)
                .foregroundStyle(Theme.Color.ink)
            Spacer(minLength: 0)
        }
    }

    private func request() async {
        requesting = true
        defer { requesting = false }
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        Haptics.success()
        app.completeOnboarding()
    }
}

#Preview {
    NotificationsScreen().environment(AppState())
}
