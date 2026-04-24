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
        // Route `suisport://` callbacks into the wallet bridge so the
        // pending sign-in continuation can resume when Slush returns.
        // Any URL the bridge doesn't recognize is a no-op.
        .onOpenURL { url in
            _ = WalletConnectBridge.shared.handleIncomingURL(url)
        }
        // Deep links from push notifications arrive via a broadcast
        // rather than the onOpenURL path — reuse the same wallet
        // bridge handler so kudos / comment pushes land the same
        // way. Future routing (e.g. suisport://feed/<id>) can branch
        // here once we add a feed-item navigator.
        .onReceive(NotificationCenter.default.publisher(
            for: PushNotifications.didReceiveDeepLink
        )) { note in
            if let url = note.userInfo?["url"] as? URL {
                _ = WalletConnectBridge.shared.handleIncomingURL(url)
            }
        }
    }
}

#Preview {
    RootView()
        .environment(AppState())
}
