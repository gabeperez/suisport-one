import SwiftUI

struct TrophyCaseView: View {
    @Environment(SocialDataService.self) private var social
    @State private var filter: TrophyCategory? = nil
    @State private var selected: Trophy?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                headline
                categoryFilter
                grid
                Color.clear.frame(height: 80)
            }
            .padding(.horizontal, Theme.Space.md)
            .padding(.top, Theme.Space.sm)
        }
        .background(Theme.Color.bg.ignoresSafeArea())
        .navigationTitle("Trophies")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $selected) { t in
            TrophyDetailSheet(trophy: t)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(Theme.Radius.xl)
        }
    }

    private var headline: some View {
        let unlocked = social.trophies.filter { !$0.isLocked }.count
        let total = social.trophies.count
        return VStack(alignment: .leading, spacing: 4) {
            Text("\(unlocked) of \(total) unlocked")
                .font(.displayS)
                .foregroundStyle(Theme.Color.ink)
            Text("Soulbound to your SuiSport profile. They're yours, forever.")
                .font(.bodyM).foregroundStyle(Theme.Color.inkSoft)
        }
    }

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(title: "All", isSelected: filter == nil) { filter = nil }
                ForEach(TrophyCategory.allCases, id: \.self) { c in
                    filterChip(title: c.title, isSelected: filter == c) {
                        filter = (filter == c ? nil : c)
                    }
                }
            }
        }
    }

    private func filterChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.select(); action()
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(isSelected ? Theme.Color.inkInverse : Theme.Color.ink)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(
                    Capsule().fill(isSelected ? Theme.Color.ink : Theme.Color.bgElevated)
                )
        }
        .buttonStyle(.plain)
    }

    private var grid: some View {
        let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return LazyVGrid(columns: cols, spacing: 12) {
            ForEach(filteredTrophies) { t in
                Button { selected = t } label: { TrophyCard(trophy: t) }
                    .buttonStyle(.plain)
            }
        }
    }

    private var filteredTrophies: [Trophy] {
        guard let f = filter else { return social.trophies }
        return social.trophies.filter { $0.category == f }
    }
}

// MARK: - Trophy card (large)

struct TrophyCard: View {
    let trophy: Trophy

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            medallion
            Text(trophy.title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Color.ink)
                .lineLimit(1)
            Text(trophy.subtitle)
                .font(.bodyS)
                .foregroundStyle(Theme.Color.inkSoft)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            rarityRow
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.lg).fill(Theme.Color.bgElevated))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .strokeBorder(trophy.isLocked ? Theme.Color.stroke : trophy.rarity.tint.opacity(0.4),
                              lineWidth: trophy.isLocked ? 1 : 1.5)
        )
    }

    private var medallion: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    trophy.isLocked
                    ? LinearGradient(colors: [Theme.Color.surface, Theme.Color.bgElevated],
                                     startPoint: .topLeading, endPoint: .bottomTrailing)
                    : LinearGradient(colors: trophy.gradient.isEmpty ? [Theme.Color.accent, Theme.Color.accentDeep]
                                                                     : trophy.gradient,
                                     startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(height: 104)
            Image(systemName: trophy.icon)
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(trophy.isLocked ? Theme.Color.inkFaint : .white)
                .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
            if trophy.isLocked {
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(Circle().fill(Color.black.opacity(0.35)))
                    }
                    Spacer()
                }
                .padding(6)
            }
        }
    }

    private var rarityRow: some View {
        HStack {
            HStack(spacing: 4) {
                Circle().fill(trophy.rarity.tint).frame(width: 6, height: 6)
                Text(trophy.rarity.title)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(trophy.rarity.tint)
            }
            Spacer()
            if trophy.isLocked {
                Text("\(Int(trophy.progress * 100))%")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Color.inkSoft)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.Color.accentDeep)
            }
        }
    }
}

// MARK: - Small trophy chip (for preview strips)

struct TrophyChip: View {
    let trophy: Trophy
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(trophy.isLocked
                          ? LinearGradient(colors: [Theme.Color.surface, Theme.Color.bgElevated],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                          : LinearGradient(colors: trophy.gradient.isEmpty ? [Theme.Color.accent, Theme.Color.accentDeep]
                                                                           : trophy.gradient,
                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 64, height: 64)
                Image(systemName: trophy.icon)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(trophy.isLocked ? Theme.Color.inkFaint : .white)
            }
            Text(trophy.title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.Color.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
    }
}

// MARK: - Trophy detail sheet

struct TrophyDetailSheet: View {
    let trophy: Trophy
    @State private var showShare = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            hero
            meta
            if trophy.isLocked {
                progress
            }
            description
            Spacer()
            if !trophy.isLocked {
                PrimaryButton(title: "Share", icon: "square.and.arrow.up",
                              tint: Theme.Color.ink, fg: Theme.Color.inkInverse) {
                    showShare = true
                }
            }
        }
        .padding(Theme.Space.lg)
        .sheet(isPresented: $showShare) {
            ShareSheet(items: [shareText])
        }
    }

    private var shareText: String {
        "I just unlocked \(trophy.title) on SuiSport — \(trophy.subtitle). Soulbound and on-chain. suisport.app"
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        trophy.isLocked
                        ? LinearGradient(colors: [Theme.Color.surface, Theme.Color.bgElevated],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: trophy.gradient.isEmpty ? [Theme.Color.accent, Theme.Color.accentDeep]
                                                                          : trophy.gradient,
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 96, height: 96)
                Image(systemName: trophy.icon)
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(trophy.isLocked ? Theme.Color.inkFaint : .white)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(trophy.title).font(.displayS).foregroundStyle(Theme.Color.ink)
                HStack(spacing: 6) {
                    Circle().fill(trophy.rarity.tint).frame(width: 6, height: 6)
                    Text(trophy.rarity.title)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(trophy.rarity.tint)
                    Text("·").foregroundStyle(Theme.Color.inkFaint)
                    Text(trophy.category.title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.Color.inkSoft)
                }
            }
            Spacer()
        }
        .padding(.top, Theme.Space.md)
    }

    private var meta: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let earned = trophy.earnedAt {
                row("Earned", Self.fmt.string(from: earned))
            }
            Divider()
            row("Soulbound to", "your Sui address")
        }
        .padding(Theme.Space.md)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.md).fill(Theme.Color.bgElevated))
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.labelBold).foregroundStyle(Theme.Color.inkSoft)
            Spacer()
            Text(v).font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.Color.ink)
        }
        .padding(.vertical, 8)
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Progress")
                    .font(.labelBold).foregroundStyle(Theme.Color.inkSoft)
                Spacer()
                Text("\(Int(trophy.progress * 100))%")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Color.ink)
            }
            ProgressBar(progress: trophy.progress, tint: trophy.rarity.tint)
                .frame(height: 10)
        }
    }

    private var description: some View {
        Text(trophy.subtitle)
            .font(.bodyM)
            .foregroundStyle(Theme.Color.inkSoft)
    }

    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; return f
    }()
}
