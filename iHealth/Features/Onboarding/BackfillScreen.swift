import SwiftUI

struct BackfillScreen: View {
    @Environment(AppState.self) private var app
    @State private var count: Int = 0
    @State private var totalPoints: Int = 0
    @State private var phase: Phase = .searching
    @State private var ringProgress: CGFloat = 0

    enum Phase { case searching, reveal }

    var body: some View {
        OnboardingShell(showsBack: false) {
            VStack(spacing: Theme.Space.lg) {
                Spacer()
                orb
                text
                Spacer()
                Spacer()
            }
            .padding(.horizontal, Theme.Space.lg)
        } actions: {
            if phase == .reveal {
                PrimaryButton(
                    title: "Let's go",
                    icon: "arrow.right",
                    tint: Theme.Color.accent,
                    fg: Theme.Color.accentInk
                ) {
                    app.advanceOnboarding()
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .task { await run() }
    }

    // MARK: - Orb

    private var orb: some View {
        ZStack {
            Circle()
                .stroke(Theme.Color.stroke, lineWidth: 8)
                .frame(width: 220, height: 220)
            Circle()
                .trim(from: 0, to: ringProgress)
                .stroke(Theme.Color.accent,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 220, height: 220)
                .animation(Theme.Motion.soft, value: ringProgress)
            VStack(spacing: 4) {
                if phase == .searching {
                    Text("\(count)")
                        .font(.numberL)
                        .foregroundStyle(Theme.Color.ink)
                        .contentTransition(.numericText())
                    Text("workouts found")
                        .font(.labelBold)
                        .foregroundStyle(Theme.Color.inkSoft)
                } else {
                    Text("\(totalPoints)")
                        .font(.numberL)
                        .foregroundStyle(Theme.Color.ink)
                        .contentTransition(.numericText())
                    Text("Sweat Points")
                        .font(.labelBold)
                        .foregroundStyle(Theme.Color.inkSoft)
                }
            }
        }
    }

    // MARK: - Text

    private var text: some View {
        VStack(spacing: Theme.Space.sm) {
            switch phase {
            case .searching:
                Text("Finding your workouts…")
                    .font(.titleL)
                    .foregroundStyle(Theme.Color.ink)
                Text("Looking through the last year of activity")
                    .font(.bodyM)
                    .foregroundStyle(Theme.Color.inkSoft)
            case .reveal:
                Text("Nice work.")
                    .font(.displayM)
                    .foregroundStyle(Theme.Color.ink)
                Text("We found **\(count)** workouts already worth your points.\nYou earned these before you even signed up.")
                    .font(.bodyL)
                    .foregroundStyle(Theme.Color.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Space.md)
            }
        }
    }

    // MARK: - Run

    private func run() async {
        withAnimation(.linear(duration: 1.6)) { ringProgress = 0.75 }

        await app.backfillWorkouts { n in
            withAnimation(Theme.Motion.snap) {
                count = n
            }
        }

        // Ensure minimum showtime so the animation doesn't snap-through
        try? await Task.sleep(nanoseconds: 700_000_000)

        let total = app.sweatPoints.total
        withAnimation(.easeInOut(duration: 0.5)) { ringProgress = 1.0 }
        Haptics.success()

        // Count up points
        let steps = 28
        let per = max(1, total / steps)
        var current = 0
        while current < total {
            current = min(total, current + per)
            withAnimation(.linear(duration: 0.04)) { totalPoints = current }
            try? await Task.sleep(nanoseconds: 30_000_000)
        }

        withAnimation(Theme.Motion.bounce) { phase = .reveal }
    }
}

#Preview {
    BackfillScreen().environment(AppState())
}
