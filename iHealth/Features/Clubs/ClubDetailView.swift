import SwiftUI

struct ClubDetailView: View {
    let clubId: UUID
    @Environment(SocialDataService.self) private var social
    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab = .activity
    @State private var selectedItem: FeedItem?
    @State private var showShare = false

    enum Tab: String, CaseIterable {
        case activity, members, treasury
        var title: String { rawValue.capitalized }
    }

    private var club: Club? { social.clubs.first(where: { $0.id == clubId }) }

    var body: some View {
        ScrollView {
            if let c = club {
                VStack(spacing: Theme.Space.md) {
                    hero(c)
                    about(c)
                    statStrip(c)
                    tabs
                    Group {
                        switch tab {
                        case .activity: activityList
                        case .members: membersGrid
                        case .treasury: treasuryCard(c)
                        }
                    }
                    Color.clear.frame(height: 80)
                }
                .padding(.horizontal, Theme.Space.md)
            } else {
                Text("Club not found").padding()
            }
        }
        .background(Theme.Color.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedItem) { item in
            WorkoutDetailView(feedItemId: item.id)
        }
        .sheet(isPresented: $showShare) {
            if let c = club {
                ShareSheet(items: [clubShareText(c)])
            }
        }
    }

    private func clubShareText(_ c: Club) -> String {
        "Join \(c.name) (@\(c.handle)) on SuiSport ONE — \(c.tagline). suisport.app"
    }

    // MARK: - Hero

    private func hero(_ c: Club) -> some View {
        ZStack(alignment: .bottomLeading) {
            c.heroTone.gradient
                .frame(height: 180)
            LinearGradient(
                colors: [.black.opacity(0), .black.opacity(0.55)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 180)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(c.name)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    if c.isVerifiedBrand {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                Text("@\(c.handle)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(Theme.Space.lg)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
    }

    // MARK: - About

    private func about(_ c: Club) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(c.tagline)
                .font(.titleM).foregroundStyle(Theme.Color.ink)
            Text(c.description)
                .font(.bodyM).foregroundStyle(Theme.Color.inkSoft)
            HStack(spacing: 8) {
                if c.isJoined {
                    PillButton(title: "Joined", icon: "checkmark",
                               tint: Theme.Color.bgElevated, fg: Theme.Color.ink) {
                        SocialDataService.shared.toggleClubMembership(c.id)
                    }
                } else {
                    PillButton(title: "Join club", icon: "plus",
                               tint: Theme.Color.ink, fg: Theme.Color.inkInverse) {
                        SocialDataService.shared.toggleClubMembership(c.id)
                    }
                }
                PillButton(title: "Share", icon: "square.and.arrow.up",
                           tint: Theme.Color.bgElevated, fg: Theme.Color.ink) {
                    showShare = true
                }
            }
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                        .fill(Theme.Color.bgElevated))
    }

    // MARK: - Stats

    private func statStrip(_ c: Club) -> some View {
        HStack(spacing: 0) {
            stat("\(c.memberCount.formatted(.number.notation(.compactName)))", "Members")
            Divider().frame(height: 30).overlay(Theme.Color.stroke)
            stat("\(c.sweatTreasury.formatted(.number.notation(.compactName)))", "Treasury")
            Divider().frame(height: 30).overlay(Theme.Color.stroke)
            stat("\(Int(c.weeklyKm)) km", "This week")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.md).fill(Theme.Color.bgElevated))
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Color.ink)
            Text(l).font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.Color.inkSoft)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Tabs

    private var tabs: some View {
        HStack(spacing: 6) {
            ForEach(Tab.allCases, id: \.self) { t in
                Button {
                    Haptics.select()
                    withAnimation(Theme.Motion.snap) { tab = t }
                } label: {
                    Text(t.title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(tab == t ? Theme.Color.ink : Theme.Color.inkSoft)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(tab == t ? Theme.Color.ink : .clear)
                                .frame(height: 2)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Activity

    private var activityList: some View {
        VStack(spacing: 10) {
            ForEach(social.feed.prefix(6)) { item in
                Button { selectedItem = item } label: {
                    AthleteActivityRow(item: item)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Members

    private var membersGrid: some View {
        let cols = [GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)]
        return LazyVGrid(columns: cols, spacing: 14) {
            ForEach(social.athletes) { a in
                VStack(spacing: 4) {
                    AthleteAvatar(athlete: a, size: 54)
                    Text(a.displayName.split(separator: " ").first.map(String.init) ?? a.handle)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.Color.ink)
                        .lineLimit(1)
                }
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Treasury

    private func treasuryCard(_ c: Club) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Treasury")
                        .font(.labelBold).foregroundStyle(Theme.Color.inkSoft)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(c.sweatTreasury.formatted(.number.notation(.compactName)))")
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                        Text("SWEAT")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.Color.inkSoft)
                    }
                }
                Spacer()
                KudosCoin(size: 40)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("How the treasury works")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.Color.ink)
                row("Auto-funded", "1% of every member's earned SWEAT.")
                row("Spent by vote", "Members stake SWEAT to vote on prizes and proposals.")
                row("Owned on Sui", "The treasury lives in a Move contract. Nobody can drain it.")
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.md)
                            .fill(Theme.Color.bgElevated))
        }
        .padding(Theme.Space.md)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.lg).fill(Theme.Color.bgElevated))
    }

    private func row(_ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkle")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.Color.accentDeep)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.Color.ink)
                Text(body).font(.bodyS).foregroundStyle(Theme.Color.inkSoft)
            }
            Spacer()
        }
    }
}
