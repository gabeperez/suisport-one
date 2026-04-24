import SwiftUI

struct AthleteProfileView: View {
    let athleteId: String
    @Environment(SocialDataService.self) private var social
    @State private var isFollowing: Bool = false
    @State private var selectedItem: FeedItem?
    @State private var showEdit = false
    @State private var showShare = false

    private var athlete: Athlete? {
        if let me = social.me, me.id == athleteId { return me }
        return social.athletes.first { $0.id == athleteId }
    }

    var body: some View {
        ScrollView {
            if let a = athlete {
                VStack(spacing: Theme.Space.md) {
                    header(a)
                    stats(a)
                    actionRow(a)
                    segmentsBadges(a)
                    trophiesPreview
                    recentActivities
                    Color.clear.frame(height: 80)
                }
                .padding(.horizontal, Theme.Space.md)
                .padding(.top, Theme.Space.sm)
            } else {
                Text("Athlete not found").padding()
            }
        }
        .background(Theme.Color.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedItem) { item in
            WorkoutDetailView(feedItemId: item.id)
        }
        .sheet(isPresented: $showEdit) { EditProfileSheet() }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: [shareText])
        }
    }

    private var shareText: String {
        guard let a = athlete else { return "SuiSport ONE" }
        return "Follow \(a.displayName) (@\(a.handle)) on SuiSport ONE — proof-of-sweat fitness on Sui. suisport.app"
    }

    private var isMe: Bool { social.me?.id == athleteId }

    // MARK: - Header

    private func header(_ a: Athlete) -> some View {
        VStack(spacing: 10) {
            AthleteAvatar(athlete: a, size: 94)
                .padding(.top, Theme.Space.md)
            HStack(spacing: 6) {
                Text(a.displayName)
                    .font(.displayS).foregroundStyle(Theme.Color.ink)
                if a.verified {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.Color.sky)
                }
            }
            Text("@\(a.handle)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.Color.inkFaint)
            tierBadge(a.tier)
            profileMeta(a)
            if let bio = a.bio, !bio.isEmpty {
                Text(bio)
                    .font(.bodyM)
                    .foregroundStyle(Theme.Color.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Space.lg)
            }
            if let link = a.websiteUrl,
               let url = URL(string: link.trimmingCharacters(in: .whitespaces)),
               url.scheme?.hasPrefix("http") == true {
                Button {
                    Haptics.tap()
                    UIApplication.shared.open(url)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .font(.system(size: 11, weight: .bold))
                        Text(url.host ?? link)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Theme.Color.accentDeep)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Pronouns + location as an inline pair under the tier badge.
    /// Hidden entirely if neither is set so we don't waste vertical
    /// space on brand-new profiles.
    @ViewBuilder
    private func profileMeta(_ a: Athlete) -> some View {
        let pieces: [String] = [a.pronouns, a.location]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if !pieces.isEmpty {
            Text(pieces.joined(separator: " · "))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.Color.inkFaint)
        }
    }

    private func tierBadge(_ tier: AthleteTier) -> some View {
        HStack(spacing: 6) {
            Circle().fill(tier.ring).frame(width: 8, height: 8)
            Text(tier.title).font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(Theme.Color.ink)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Capsule().fill(Theme.Color.bgElevated))
        .overlay(Capsule().strokeBorder(tier.ring.opacity(0.5), lineWidth: 1))
    }

    // MARK: - Stats

    private func stats(_ a: Athlete) -> some View {
        HStack(spacing: 0) {
            stat("\(a.totalWorkouts)", "Workouts")
            Divider().frame(height: 30).overlay(Theme.Color.stroke)
            stat("\(a.followers.formatted(.number.notation(.compactName)))", "Followers")
            Divider().frame(height: 30).overlay(Theme.Color.stroke)
            stat("\(a.following.formatted(.number.notation(.compactName)))", "Following")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Theme.Color.bgElevated)
        )
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Color.ink)
            Text(label).font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.Color.inkSoft)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private func actionRow(_ a: Athlete) -> some View {
        HStack(spacing: 8) {
            if isMe {
                PillButton(title: "Edit profile", icon: "pencil",
                           tint: Theme.Color.bgElevated, fg: Theme.Color.ink) {
                    showEdit = true
                }
                PillButton(title: "Share", icon: "square.and.arrow.up",
                           tint: Theme.Color.bgElevated, fg: Theme.Color.ink) {
                    showShare = true
                }
            } else {
                PillButton(
                    title: isFollowing ? "Following" : "Follow",
                    icon: isFollowing ? "checkmark" : "plus",
                    tint: isFollowing ? Theme.Color.bgElevated : Theme.Color.ink,
                    fg: isFollowing ? Theme.Color.ink : Theme.Color.inkInverse
                ) { isFollowing.toggle() }
                PillButton(title: "Share", icon: "square.and.arrow.up",
                           tint: Theme.Color.bgElevated, fg: Theme.Color.ink) {
                    showShare = true
                }
            }
        }
    }

    // MARK: - Segments / badges strip

    private func segmentsBadges(_ a: Athlete) -> some View {
        // KOMs and Challenges aren't on the Athlete DTO yet — we used to
        // fabricate them with Int.random which shipped bogus numbers on real
        // profiles. Show zero with a "Soon" hint until the backend exposes
        // them. Trophies are real only for the signed-in user; for other
        // athletes we don't have their count yet so we mark it Soon too.
        HStack(spacing: 12) {
            smallStat(icon: "crown.fill",
                      label: "KOMs",
                      value: "0",
                      tint: Theme.Color.gold,
                      isPlaceholder: true)
            smallStat(icon: "flag.checkered",
                      label: "Challenges",
                      value: "0",
                      tint: Theme.Color.violet,
                      isPlaceholder: true)
            if isMe {
                smallStat(icon: "trophy.fill",
                          label: "Trophies",
                          value: "\(social.trophies.filter { !$0.isLocked }.count)",
                          tint: Theme.Color.hot,
                          isPlaceholder: false)
            } else {
                smallStat(icon: "trophy.fill",
                          label: "Trophies",
                          value: "0",
                          tint: Theme.Color.hot,
                          isPlaceholder: true)
            }
        }
    }

    private func smallStat(icon: String,
                           label: String,
                           value: String,
                           tint: Color,
                           isPlaceholder: Bool) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(isPlaceholder ? Theme.Color.inkFaint : tint)
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(isPlaceholder ? Theme.Color.inkFaint : Theme.Color.ink)
            }
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.Color.inkSoft)
                if isPlaceholder {
                    Text("soon")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .tracking(0.4)
                        .foregroundStyle(Theme.Color.inkFaint)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Capsule().fill(Theme.Color.surface))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.md).fill(Theme.Color.bgElevated))
    }

    // MARK: - Trophies preview

    @ViewBuilder
    private var trophiesPreview: some View {
        if !social.trophies.isEmpty {
            NavigationLink { TrophyCaseView() } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Trophy case")
                            .font(.titleM).foregroundStyle(Theme.Color.ink)
                        Spacer()
                        Text("See all")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.Color.inkSoft)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.Color.inkFaint)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(social.trophies.prefix(8)) { t in
                                TrophyChip(trophy: t)
                                    .frame(width: 86)
                            }
                        }
                    }
                }
                .padding(Theme.Space.md)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.lg).fill(Theme.Color.bgElevated))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Activities

    private var recentActivities: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent")
                .font(.titleM)
                .foregroundStyle(Theme.Color.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(social.feed.filter { $0.athlete.id == athleteId }.prefix(6)) { item in
                Button { selectedItem = item } label: {
                    AthleteActivityRow(item: item)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Small recent-activity row

struct AthleteActivityRow: View {
    let item: FeedItem

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(item.athlete.avatarTone.gradient.opacity(0.25))
                    .frame(width: 48, height: 48)
                Image(systemName: item.workout.type.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.Color.ink)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.Color.ink)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Color.inkSoft)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("+\(item.workout.points)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Color.ink)
                HStack(spacing: 8) {
                    HStack(spacing: 3) {
                        Image(systemName: "bolt.heart.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.Color.hot)
                        Text("\(item.kudosCount)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.Color.inkSoft)
                    }
                    HStack(spacing: 3) {
                        Image(systemName: "bubble.left.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.Color.sky)
                        Text("\(item.commentCount)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.Color.inkSoft)
                    }
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.md).fill(Theme.Color.bgElevated))
    }

    private var subtitle: String {
        var parts: [String] = []
        parts.append(Self.fmt.string(from: item.workout.startDate))
        if let d = item.workout.distanceMeters, d > 0 {
            parts.append(String(format: "%.2f km", d / 1000))
        }
        return parts.joined(separator: " · ")
    }

    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return f
    }()
}
