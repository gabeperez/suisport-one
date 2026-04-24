import Foundation
import UIKit
import UserNotifications

/// Apple Push Notification service registration + handling.
///
/// Flow:
///   1. On first-launch (or when the user opts in from onboarding) we
///      call `requestAuthorization`.
///   2. If granted, iOS gives us back a device token via the
///      `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`
///      delegate callback.
///   3. We hex-encode the token and POST it to /v1/account/push-token.
///   4. APNs-triggered pushes arrive via
///      `userNotificationCenter(_:didReceive:withCompletionHandler:)`
///      which extracts a `deepLink` payload and tells the UI to route.
///
/// We keep it simple: no categories with actions, no rich
/// notifications. The server decides the body; we just render +
/// route. Categories are tagged so iOS groups them in Notification
/// Center (one thread per feed item).
@MainActor
final class PushNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PushNotifications()

    /// Broadcast name RootView subscribes to so notification taps
    /// can route into the app. The userInfo carries a `url: URL`.
    static let didReceiveDeepLink = Notification.Name("SuiSport.didReceiveDeepLink")

    private let center = UNUserNotificationCenter.current()
    private let tokenDefaultsKey = "SuiSport.apns.lastUploadedToken"

    func configure() {
        center.delegate = self
    }

    /// Prompt the user for permission. Safe to call repeatedly — iOS
    /// caches the decision and subsequent calls return immediately.
    /// Returns true if notifications are allowed at all (even
    /// provisional). On grant, triggers iOS registration so we get a
    /// device token.
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
            return granted
        } catch {
            return false
        }
    }

    /// Called from AppDelegate on successful APNs registration. Hex-
    /// encodes the raw bytes and uploads if changed since last time.
    func handleRegistered(deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        let last = UserDefaults.standard.string(forKey: tokenDefaultsKey)
        guard hex != last else { return }
        Task { await upload(hex: hex) }
    }

    func handleRegisterFailed(error: Error) {
        // Silent in production; surface via logs.
        print("APNs registration failed:", error)
    }

    private func upload(hex: String) async {
        // Use the same APIClient wrapper, but inline the path because
        // account.ts exposes this endpoint without a dedicated helper.
        let url = APIClient.shared.baseURL.appendingPathComponent("/account/push-token")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let tok = APIClient.shared.sessionToken {
            req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
        }
        #if DEBUG
        let env = "sandbox"
        #else
        let env = "production"
        #endif
        req.httpBody = try? JSONSerialization.data(
            withJSONObject: ["token": hex, "env": env]
        )
        _ = try? await URLSession.shared.data(for: req)
        UserDefaults.standard.set(hex, forKey: tokenDefaultsKey)
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Called when a notification arrives with the app foregrounded.
    /// We show the banner + sound so the user sees the ping; iOS
    /// suppresses them by default.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    /// Called when the user taps the notification. Extract the
    /// deepLink payload and stash it for RootView to route via
    /// .onOpenURL.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let link = response.notification.request.content.userInfo["deepLink"] as? String,
           let url = URL(string: link) {
            NotificationCenter.default.post(
                name: Self.didReceiveDeepLink,
                object: nil,
                userInfo: ["url": url]
            )
        }
        completionHandler()
    }
}
