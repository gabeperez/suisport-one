import SwiftUI

enum RootTab: Hashable { case feed, clubs, explore, you }

struct RootTabView: View {
    @Environment(AppState.self) private var app
    @Environment(SocialDataService.self) private var social
    @State private var tab: RootTab = .feed
    @State private var showRecord = false

    var body: some View {
        ZStack(alignment: .bottom) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            tabBar
        }
        .sheet(isPresented: $showRecord) {
            RecordSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(Theme.Radius.xl)
        }
        .background(Theme.Color.bg.ignoresSafeArea())
        .task {
            // Mirror the AppState toggle into the data service so
            // refresh() can short-circuit when the user wants to
            // stage-demo with rich fixture data.
            social.demoOverride = app.showDemoData
            await social.refresh()
        }
        .onChange(of: app.showDemoData) { _, newValue in
            social.demoOverride = newValue
            // Re-seed the local fixtures when the user flips the
            // toggle ON, so they get a fresh, full set even if a
            // previous refresh had partially overwritten them.
            if newValue {
                SocialDataService.shared.reset()
                SocialDataService.shared.seed(for: app.currentUser, workouts: app.workouts)
            } else {
                Task { await social.refresh() }
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .feed: FeedView()
        case .clubs: ClubsView()
        case .explore: ExploreView()
        case .you: ProfileView()
        }
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            tabItem(.feed, icon: "bolt.heart.fill", label: "Feed")
            tabItem(.clubs, icon: "person.3.fill", label: "Clubs")
            recordButton
            tabItem(.explore, icon: "safari.fill", label: "Explore")
            tabItem(.you, icon: "person.crop.circle.fill", label: "You")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().strokeBorder(Theme.Color.stroke, lineWidth: 1))
                .shadow(color: .black.opacity(0.1), radius: 24, y: 8)
        )
        .padding(.horizontal, Theme.Space.md)
        .padding(.bottom, Theme.Space.sm)
    }

    private func tabItem(_ t: RootTab, icon: String, label: String) -> some View {
        Button {
            Haptics.tap()
            withAnimation(Theme.Motion.snap) { tab = t }
        } label: {
            let selected = tab == t
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                Text(label)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(selected ? Theme.Color.ink : Theme.Color.inkFaint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private var recordButton: some View {
        Button {
            Haptics.thud()
            showRecord = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.Color.accentInk)
                .frame(width: 58, height: 58)
                .background(Circle().fill(Theme.Color.accent))
                .shadow(color: Theme.Color.accent.opacity(0.5), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 2)
    }
}
