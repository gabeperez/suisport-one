import SwiftUI

struct ClubsView: View {
    @Environment(SocialDataService.self) private var social
    @State private var filter: ClubFilter = .forYou
    @State private var selectedClub: Club?
    @State private var showCreate = false

    enum ClubFilter: String, CaseIterable {
        case forYou, joined, brands
        var title: String {
            switch self {
            case .forYou: return "For you"
            case .joined: return "Joined"
            case .brands: return "Brands"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Space.md) {
                    heroHeader
                    filterRow
                    if filter == .forYou { featuredCard }
                    ForEach(filteredClubs) { club in
                        Button { selectedClub = club } label: {
                            ClubRow(club: club)
                        }
                        .buttonStyle(.plain)
                    }
                    Color.clear.frame(height: 120)
                }
                .padding(.horizontal, Theme.Space.md)
                .padding(.top, Theme.Space.sm)
            }
            .background(Theme.Color.bg.ignoresSafeArea())
            .refreshable { await social.refresh() }
            .navigationTitle("Clubs")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.tap()
                        showCreate = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
            }
            .navigationDestination(item: $selectedClub) { club in
                ClubDetailView(clubId: club.id)
            }
            .sheet(isPresented: $showCreate) { CreateClubSheet() }
        }
    }

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Find your crew")
                .font(.displayS).foregroundStyle(Theme.Color.ink)
            Text("Run with your people. Own the treasury together.")
                .font(.bodyM).foregroundStyle(Theme.Color.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var filterRow: some View {
        HStack(spacing: 8) {
            ForEach(ClubFilter.allCases, id: \.self) { f in
                Button {
                    Haptics.select()
                    withAnimation(Theme.Motion.snap) { filter = f }
                } label: {
                    Text(f.title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(filter == f ? Theme.Color.inkInverse : Theme.Color.ink)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(
                            Capsule().fill(filter == f ? Theme.Color.ink : Theme.Color.bgElevated)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var featuredCard: some View {
        if let club = social.clubs.first(where: { $0.isVerifiedBrand }) {
            Button { selectedClub = club } label: {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .bold))
                        Text("FEATURED")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(1.2)
                    }
                    .foregroundStyle(.white.opacity(0.8))

                    Text(club.name)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(club.tagline)
                        .font(.bodyM)
                        .foregroundStyle(.white.opacity(0.85))
                    HStack(spacing: 16) {
                        featureStat("Members", "\(club.memberCount.formatted(.number.notation(.compactName)))")
                        featureStat("Treasury", "\(club.sweatTreasury.formatted(.number.notation(.compactName))) Sweat")
                        featureStat("Week", "\(Int(club.weeklyKm)) km")
                    }
                }
                .padding(Theme.Space.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
                        .fill(club.heroTone.gradient)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func featureStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private var filteredClubs: [Club] {
        switch filter {
        case .forYou: return social.clubs
        case .joined: return social.clubs.filter { $0.isJoined }
        case .brands: return social.clubs.filter { $0.isVerifiedBrand }
        }
    }
}

struct ClubRow: View {
    let club: Club

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(club.heroTone.gradient)
                    .frame(width: 56, height: 56)
                Text(emoji(for: club))
                    .font(.system(size: 26))
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(club.name)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.Color.ink)
                    if club.isVerifiedBrand {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.Color.sky)
                    }
                }
                Text(club.tagline)
                    .font(.bodyS)
                    .foregroundStyle(Theme.Color.inkSoft)
                    .lineLimit(1)
                HStack(spacing: 10) {
                    label(icon: "person.2.fill",
                          text: "\(club.memberCount.formatted(.number.notation(.compactName)))")
                    label(icon: "bolt.heart.fill",
                          text: "\(club.sweatTreasury.formatted(.number.notation(.compactName)))")
                }
            }
            Spacer()
            if club.isJoined {
                Text("Joined")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.Color.accentDeep)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Theme.Color.accent.opacity(0.18)))
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.Color.inkFaint)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.md).fill(Theme.Color.bgElevated))
    }

    private func label(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.Color.inkFaint)
            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.Color.inkSoft)
        }
    }

    private func emoji(for club: Club) -> String {
        let bag: [String]
        if club.tags.contains("cycling") { bag = ["🚴", "🏁", "🛞"] }
        else if club.tags.contains("trail") { bag = ["🏔️", "🥾", "🌲"] }
        else if club.tags.contains("strength") { bag = ["🏋️", "💪", "🔩"] }
        else if club.tags.contains("marathon") { bag = ["🏃", "🥇", "🎯"] }
        else { bag = ["🏃", "⚡", "🔥"] }
        let idx = abs(club.name.hashValue) % bag.count
        return bag[idx]
    }
}
