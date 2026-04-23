import SwiftUI

/// Router between onboarding and main app. The @Observable AppState lives at app root.
struct RootView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        ZStack {
            if app.hasCompletedOnboarding {
                RootTabView()
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 1.02)),
                        removal: .opacity
                    ))
            } else {
                OnboardingCoordinator()
                    .transition(.opacity)
            }
        }
        .animation(Theme.Motion.soft, value: app.hasCompletedOnboarding)
    }
}

#Preview {
    RootView()
        .environment(AppState())
}
