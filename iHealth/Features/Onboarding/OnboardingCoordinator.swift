import SwiftUI

struct OnboardingCoordinator: View {
    @Environment(AppState.self) private var app

    var body: some View {
        ZStack {
            switch app.onboardingStep {
            case .hero:
                HeroScreen()
                    .transition(.opacity)
            case .auth:
                AuthScreen()
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            case .nameGoal:
                NameGoalScreen()
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            case .healthPermission:
                HealthPermissionScreen()
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            case .backfill:
                BackfillScreen()
                    .transition(.opacity)
            case .notifications:
                NotificationsScreen()
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity
                    ))
            case .ageGate:
                AgeGateScreen()
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
        }
        .animation(Theme.Motion.soft, value: app.onboardingStep)
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
