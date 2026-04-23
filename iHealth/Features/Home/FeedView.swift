import SwiftUI

struct FeedView: View {
    @Environment(AppState.self) private var app
    @Environment(SocialDataService.self) private var social

    @State private var selectedItem: FeedItem?
    @State private var selectedAthlete: Athlete?
    @State private var showStreakSheet = false
    @State private var showSortSheet = false
    @State private var sort: FeedSortSheet.FeedSort = .recent
    @State private var filter: FeedFilter = .following
    @State private var reportingItem: FeedItem?

    enum FeedFilter: String, CaseIterable { case following, discover
        var title: String { self == .following ? "Following" : "Discover" }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Space.md) {
                    headerBar
                    pointsCard
                    streakCard
                    filterRow
                    feedList
                    Color.clear.frame(height: 120)
                }
                .padding(.horizontal, Theme.Space.md)
                .padding(.top, Theme.Space.sm)
            }
            .refreshable { await social.refresh() }
            .background(Theme.Color.bg.ignoresSafeArea())
            .navigationDestination(item: $selectedItem) { item in
                WorkoutDetailView(feedItemId: item.id)
            }
            .navigationDestination(item: $selectedAthlete) { a in
                AthleteProfileView(athleteId: a.id)
            }
            .sheet(isPresented: $showStreakSheet) {
                StreakSheet()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(Theme.Radius.xl)
            }
            .sheet(isPresented: $showSortSheet) {
                FeedSortSheet(sort: $sort)
            }
            .confirmationDialog(
                "Report this activity?",
                isPresented: Binding(
                    get: { reportingItem != nil },
                    set: { if !$0 { reportingItem = nil } }
                ),
                titleVisibility: .visible,
                presenting: reportingItem
            ) { item in
                Button("Spam or fake workout", role: .destructive) {
                    SocialDataService.shared.reportFeedItem(item.id, reason: "spam")
                    Haptics.success()
                }
                Button("Inappropriate content", role: .destructive) {
                    SocialDataService.shared.reportFeedItem(item.id, reason: "inappropriate")
                    Haptics.success()
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("We'll hide it from your feed and review.")
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Hey, \(firstName)")
                        .font(.displayS)
                        .foregroundStyle(Theme.Color.ink)
                    DemoChip()
                }
                Text(streakLine)
                    .font(.bodyM)
                    .foregroundStyle(Theme.Color.inkSoft)
            }
            Spacer()
            if let me = social.me {
                Button { selectedAthlete = me } label: {
                    AthleteAvatar(athlete: me, size: 40)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Points card

    private var pointsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.heart.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text("Sweat Points")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(Theme.Color.accentInk.opacity(0.75))

            Text("\(app.sweatPoints.total)")
                .font(.numberXL)
                .foregroundStyle(Theme.Color.accentInk)
                .contentTransition(.numericText())

            HStack(spacing: Theme.Space.md) {
                stat(label: "This week", value: "+\(app.sweatPoints.weekly)")
                Divider().frame(height: 26).overlay(Theme.Color.accentInk.opacity(0.15))
                stat(label: "Multiplier",
                     value: String(format: "x%.2f", social.streak.multiplier))
            }
        }
        .padding(Theme.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
                .fill(Theme.Gradient.accent)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
                .strokeBorder(.white.opacity(0.2), lineWidth: 1)
        )
    }

    private func stat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.Color.accentInk.opacity(0.65))
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Color.accentInk)
        }
    }

    // MARK: - Streak card

    private var streakCard: some View {
        Button {
            Haptics.tap()
            showStreakSheet = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.Color.hot.opacity(0.14))
                        .frame(width: 52, height: 52)
                    Image(systemName: "flame.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.Color.hot)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(social.streak.currentDays)-day streak")
                        .font(.titleM).foregroundStyle(Theme.Color.ink)
                    Text(streakSubtitle)
                        .font(.bodyS).foregroundStyle(Theme.Color.inkSoft)
                }
                Spacer()
                if social.streak.stakedSweat > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                        Text("\(social.streak.stakedSweat)")
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.Color.accentDeep)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Theme.Color.accent.opacity(0.2)))
                } else {
                    Text("Stake")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.Color.ink)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Capsule().fill(Theme.Color.bgElevated))
                        .overlay(Capsule().strokeBorder(Theme.Color.stroke, lineWidth: 1))
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(Theme.Color.bgElevated)
            )
        }
        .buttonStyle(.plain)
    }

    private var streakSubtitle: String {
        if social.streak.isAtRisk, let hrs = social.streak.hoursUntilAtRisk {
            return "At risk — \(hrs)h left today"
        }
        return "Longest: \(social.streak.longestDays) days · \(social.streak.weeklyStreakWeeks)w weekly"
    }

    // MARK: - Filter row

    private var filterRow: some View {
        HStack(spacing: 8) {
            ForEach(FeedFilter.allCases, id: \.self) { f in
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
            Button {
                Haptics.tap()
                showSortSheet = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Color.inkSoft)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Theme.Color.bgElevated))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Feed list

    @ViewBuilder
    private var feedList: some View {
        if social.feed.isEmpty {
            emptyState
        } else {
            ForEach(filteredFeed) { item in
                FeedCard(
                    item: item,
                    onTap: { selectedItem = item },
                    onAthleteTap: { selectedAthlete = item.athlete },
                    onKudosTap: { tip in
                        SocialDataService.shared.toggleKudos(on: item.id, tip: tip)
                    },
                    onMute: {
                        SocialDataService.shared.muteAthlete(item.athlete.id)
                        Haptics.success()
                    },
                    onReport: { reportingItem = item }
                )
            }
        }
    }

    private var filteredFeed: [FeedItem] {
        let base = filter == .following ? social.feed : social.feed.shuffled()
        switch sort {
        case .recent:
            return base.sorted { $0.workout.startDate > $1.workout.startDate }
        case .mostKudos:
            return base.sorted { $0.kudosCount > $1.kudosCount }
        case .closestFriends:
            return base
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Space.sm) {
            Image(systemName: "figure.run")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(Theme.Color.inkFaint)
            Text("No activity yet").font(.titleM)
            Text("Tap the + to start your first recorded workout.")
                .font(.bodyM)
                .foregroundStyle(Theme.Color.inkSoft)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Space.xl)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .fill(Theme.Color.bgElevated)
        )
    }

    // MARK: - Derived

    private var firstName: String {
        (app.currentUser?.displayName ?? "")
            .split(separator: " ").first.map(String.init) ?? "friend"
    }

    private var streakLine: String {
        let s = social.streak.currentDays
        if s > 1 { return "\(s)-day streak. Don't break it." }
        if s == 1 { return "Day 1. Let's stack it." }
        return "Ready when you are."
    }
}

// MARK: - Feed card

struct FeedCard: View {
    let item: FeedItem
    let onTap: () -> Void
    let onAthleteTap: () -> Void
    let onKudosTap: (Int) -> Void
    let onMute: () -> Void
    let onReport: () -> Void

    @State private var kudosBurst = false
    @State private var showShare = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            titleBlock
            mapPreview
            statsRow
            if let caption = item.caption, !caption.isEmpty {
                Text(caption)
                    .font(.bodyM)
                    .foregroundStyle(Theme.Color.ink)
                    .padding(.top, 2)
            }
            actionsRow
            if item.commentCount > 0 {
                commentPeek
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .fill(Theme.Color.bgElevated)
        )
        .contentShape(Rectangle())
    }

    // MARK: Subviews

    private var header: some View {
        HStack(spacing: 10) {
            Button { onAthleteTap() } label: {
                AthleteAvatar(athlete: item.athlete, size: 40)
            }.buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Button { onAthleteTap() } label: {
                        Text(item.athlete.displayName)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.Color.ink)
                    }.buttonStyle(.plain)
                    if item.workout.verified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.Color.accentDeep)
                    }
                }
                Text(relative(from: item.workout.startDate))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.Color.inkFaint)
            }
            Spacer()
            Menu {
                Button { onAthleteTap() } label: { Label("View profile", systemImage: "person.crop.circle") }
                Button { onMute() } label: { Label("Mute \(item.athlete.displayName)", systemImage: "speaker.slash") }
                Button(role: .destructive) { onReport() } label: {
                    Label("Report", systemImage: "exclamationmark.bubble")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(Theme.Color.inkFaint)
                    .frame(width: 28, height: 28)
            }
        }
    }

    private var titleBlock: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: item.workout.type.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Color.accentDeep)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Theme.Color.accent.opacity(0.14)))
                Text(item.title)
                    .font(.titleM)
                    .foregroundStyle(Theme.Color.ink)
                    .lineLimit(1)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "bolt.heart.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text("+\(item.workout.points)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .foregroundStyle(Theme.Color.accentDeep)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var mapPreview: some View {
        Button(action: onTap) {
            FakeMapPreview(seed: item.mapPreviewSeed, tone: item.athlete.avatarTone)
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var statsRow: some View {
        HStack(spacing: 18) {
            if let d = item.workout.distanceMeters, d > 0 {
                stat("Distance", String(format: "%.2f km", d / 1000))
            }
            stat("Time", formatDuration(item.workout.duration))
            if let hr = item.workout.avgHeartRate {
                stat("Avg HR", "\(Int(hr)) bpm")
            } else if let p = item.workout.paceSecondsPerKm {
                stat("Pace", paceString(p))
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.Color.inkFaint)
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Color.ink)
        }
    }

    private var actionsRow: some View {
        HStack(spacing: 12) {
            kudosButton
            commentButton
            tipBadge
            Spacer()
            shareButton
        }
    }

    private var kudosButton: some View {
        Button {
            let tip = Int.random(in: 0...3) == 0 ? 1 : 0
            withAnimation(Theme.Motion.bounce) { kudosBurst = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                kudosBurst = false
            }
            Haptics.pop()
            onKudosTap(tip)
        } label: {
            HStack(spacing: 6) {
                ZStack {
                    Image(systemName: item.userHasKudosed ? "bolt.heart.fill" : "bolt.heart")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(item.userHasKudosed ? Theme.Color.hot : Theme.Color.ink)
                        .scaleEffect(kudosBurst ? 1.35 : 1.0)
                    if kudosBurst {
                        KudosCoin(size: 16)
                            .offset(y: -28)
                            .opacity(kudosBurst ? 0 : 1)
                            .animation(.easeOut(duration: 0.5), value: kudosBurst)
                    }
                }
                Text("\(item.kudosCount)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(Theme.Color.ink)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Capsule().fill(Theme.Color.surface))
        }
        .buttonStyle(.plain)
    }

    private var commentButton: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 14, weight: .semibold))
                Text("\(item.commentCount)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(Theme.Color.ink)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Capsule().fill(Theme.Color.surface))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var tipBadge: some View {
        if item.tippedSweat > 0 {
            HStack(spacing: 5) {
                KudosCoin(size: 14)
                Text("\(item.tippedSweat) tipped")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(Theme.Color.gold)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(Capsule().fill(Theme.Color.gold.opacity(0.12)))
        }
    }

    private var shareButton: some View {
        Button {
            Haptics.tap()
            showShare = true
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Color.ink)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Theme.Color.surface))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showShare) {
            ShareSheet(items: [shareText])
        }
    }

    private var shareText: String {
        let who = item.athlete.displayName
        let what = item.title
        return "\(who) just hit \(what) on SuiSport. Verified on-chain. suisport.app"
    }

    private var commentPeek: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                if let first = item.comments.first {
                    AthleteAvatar(athlete: first.athlete, size: 22, showsTierRing: false)
                    Text("**\(first.athlete.displayName.split(separator: " ").first.map(String.init) ?? "")** \(first.body)")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Color.inkSoft)
                        .lineLimit(1)
                    Spacer()
                }
            }
            .padding(.top, 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func formatDuration(_ t: TimeInterval) -> String {
        let total = Int(t)
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m) min"
    }

    private func paceString(_ secPerKm: Double) -> String {
        let m = Int(secPerKm) / 60
        let s = Int(secPerKm) % 60
        return String(format: "%d:%02d /km", m, s)
    }

    private func relative(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        switch interval {
        case ..<60: return "just now"
        case ..<3600: return "\(Int(interval / 60))m ago"
        case ..<86_400: return "\(Int(interval / 3600))h ago"
        case ..<604_800: return "\(Int(interval / 86_400))d ago"
        default:
            let f = DateFormatter()
            f.dateFormat = "MMM d"
            return f.string(from: date)
        }
    }
}

#Preview {
    FeedView()
        .environment(AppState())
        .environment(SocialDataService.shared)
}
