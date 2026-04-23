import SwiftUI

struct ExploreView: View {
    @State private var tab: Tab = .challenges

    enum Tab: String, CaseIterable {
        case challenges, segments
        var title: String { rawValue.capitalized }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                topTabs
                    .padding(.horizontal, Theme.Space.md)
                    .padding(.top, Theme.Space.sm)
                Group {
                    switch tab {
                    case .challenges: ChallengesView()
                    case .segments: SegmentsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Theme.Color.bg.ignoresSafeArea())
            .navigationTitle("Explore")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var topTabs: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { t in
                Button {
                    Haptics.select()
                    withAnimation(Theme.Motion.snap) { tab = t }
                } label: {
                    VStack(spacing: 6) {
                        Text(t.title)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(tab == t ? Theme.Color.ink : Theme.Color.inkSoft)
                        Rectangle()
                            .fill(tab == t ? Theme.Color.ink : .clear)
                            .frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
