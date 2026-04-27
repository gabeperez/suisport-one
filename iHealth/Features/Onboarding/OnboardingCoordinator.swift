import SwiftUI

struct OnboardingCoordinator: View {
    @Environment(AppState.self) private var app

    var body: some View {
        ZStack {
            switch app.onboardingStep {
            case .hero:             HeroScreen().transition(.opacity)
            case .ageGate:          AgeGateScreen().transition(.opacity)
            case .auth:             AuthScreen().transition(.opacity)
            case .nameGoal:         NameGoalScreen().transition(.opacity)
            case .healthPermission: HealthPermissionScreen().transition(.opacity)
            case .backfill:         BackfillScreen().transition(.opacity)
            case .notifications:    NotificationsScreen().transition(.opacity)
            }
        }
        // Cross-fade only — slide+fade asymmetrics on a 0.6s spring made
        // every step change feel like a 1+ second wait on simulator.
        // 0.18s easeOut feels near-instant while still giving the brain
        // a frame of "something happened."
        .animation(Theme.Motion.linearFast, value: app.onboardingStep)
    }
}

/// Common chrome: step dots at top, content in middle, CTAs at bottom.
struct OnboardingShell<Content: View, Actions: View>: View {
    @Environment(AppState.self) private var app
    var showsBack: Bool = false
    @ViewBuilder let content: () -> Content
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(spacing: 0) {
            header
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(spacing: 10) {
                actions()
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.bottom, Theme.Space.md)
        }
        .background(Theme.Color.bg.ignoresSafeArea())
    }

    private var header: some View {
        HStack {
            if showsBack {
                Button {
                    Haptics.tap()
                    if let prev = OnboardingStep(rawValue: app.onboardingStep.rawValue - 1) {
                        app.onboardingStep = prev
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.Color.inkSoft)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Theme.Color.bgElevated))
                }
                .buttonStyle(.plain)
            } else {
                Spacer().frame(width: 36, height: 36)
            }
            Spacer()
            if app.onboardingStep.showsProgress {
                StepDots(total: OnboardingStep.progressStepCount,
                         index: app.onboardingStep.progressIndex)
            }
            Spacer()
            Spacer().frame(width: 36, height: 36)
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.top, Theme.Space.sm)
    }
}
