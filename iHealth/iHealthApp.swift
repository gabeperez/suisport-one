import SwiftUI

@main
struct iHealthApp: App {
    @State private var appState = AppState()
    @State private var social = SocialDataService.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(social)
                .preferredColorScheme(nil)
        }
    }
}
