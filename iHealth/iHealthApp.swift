import SwiftUI
import UIKit

@main
struct iHealthApp: App {
    @State private var appState = AppState()
    @State private var social = SocialDataService.shared
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(social)
                .preferredColorScheme(nil)
        }
    }
}

/// UIApplicationDelegate stand-in for the tiny bits SwiftUI doesn't
/// have a native hook for — APNs device-token delivery and the
/// push-notification permission grant. Everything else stays in
/// SwiftUI land.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions:
            [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Task { @MainActor in
            PushNotifications.shared.configure()
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            PushNotifications.shared.handleRegistered(deviceToken: deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            PushNotifications.shared.handleRegisterFailed(error: error)
        }
    }
}
