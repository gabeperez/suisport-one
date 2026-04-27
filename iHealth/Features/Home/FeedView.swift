import SwiftUI

struct FeedView: View {
    @Environment(AppState.self) private var app
    @Environment(SocialDataService.self) private var social

    @State private var selectedItem: FeedItem?
    @State private var selectedAthlete: Athlete?
    @State private var selectedChallenge: Challenge?
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
                    if social.lastRefreshError {
                        offlineBanner
                    }
                    samuraiCard
                    pointsCard
                    streakCard
                    filterRow
                    feedList
                    Color.clear.frame(height: 120)
                }
                .padding(.horizontal, Theme.Space.md)
                .padding(.top, Theme.Space.sm)
                // Cap content width on iPad — iOS stretches a ScrollView
                // edge-to-edge by default, which makes feed cards look
                // absurdly wide. 640pt matches a comfortable reading
                // measure for most device classes.
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .refreshable { await social.refresh() }
            .background(Theme.Color.bg.ignoresSafeArea())
            .navigationDestination(item: $selectedItem) { item in
                WorkoutDetailView(feedItemId: item.id)
            }
            .navigationDestination(item: $selectedAthlete) { a in
                AthleteProfileView(athleteId: a.id)
            }
            .navigationDestination(item: $selectedChallenge) { c in
                ChallengeDetailView(challengeId: c.id)
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

    // MARK: - Offline / error banner

    private var offlineBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: social.isOffline ? "wifi.slash" : "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.Color.hot)
            Text("Couldn't refresh feed — check your connection.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.Color.ink)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button {
                Haptics.tap()
                Task { await social.refresh() }
            } label: {
                Text("Retry")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Color.inkInverse)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Theme.Color.ink))
            }
            .buttonStyle(.plain)
            .disabled(social.isRefreshing)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Theme.Color.hot.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .strokeBorder(Theme.Color.hot.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - ONE Samurai 1 hero card
    //
    // The headline pinned-to-feed card during the hackathon window.
    // Shows the official ONE Samurai 1 event details + a live
    // countdown to fight night + the user's progress in the camp.
    //
    // Tapping the card jumps to the Samurai challenge in Explore →
    // Challenges. If we ever lose the underlying challenge the card
    // gracefully hides itself.

    private static let samuraiFightDate: Date = {
        // Wed, April 29, 2026 — Ariake Arena Tokyo. JST = UTC+9.
        var c = DateComponents()
        c.year = 2026; c.month = 4; c.day = 29
        c.hour = 17; c.minute = 0
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")
        return Calendar(identifier: .gregorian).date(from: c) ?? .now
    }()

    @ViewBuilder
    private var samuraiCard: some View {
        if let camp = social.challenges.first(where: {
            $0.title.contains("ONE Samurai 1")
        }) {
            Button {
                Haptics.tap()
                selectedChallenge = camp
            } label: {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Circle().fill(Color(red: 0.85, green: 0.02, blue: 0.16))
                                    .frame(width: 6, height: 6)
                                Text("ONE SAMURAI 1")
                                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                                    .tracking(0.16)
                                    .foregroundStyle(.white.opacity(0.9))
                            }
                            Text("Train for fight night.")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineSpacing(-2)
                            Text("Wed, Apr 29 · Ariake Arena Tokyo")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        Spacer()
                        countdownPill
                    }

                    progressStrip(camp)

                    HStack(spacing: 8) {
                        ForEach(headlineFighters.prefix(4), id: \.id) { a in
                            AthleteAvatar(athlete: a, size: 28, showsTierRing: false)
                        }
                        Text("\(camp.participants.formatted(.number.notation(.compactName))) training")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.85))
                        Spacer()
                        Text(camp.isJoined ? "Open camp →" : "Join →")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
                .padding(Theme.Space.lg)
                .frame(maxWidth: .infinity)
                .background(
                    ZStack(alignment: .topTrailing) {
                        // Deep ONE-red → black gradient hero.
                        LinearGradient(
                            colors: [
                                Color(red: 0.06, green: 0.06, blue: 0.07),
                                Color(red: 0.20, green: 0.04, blue: 0.06),
                                Color(red: 0.85, green: 0.02, blue: 0.16),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        // Faint sun-disc — Japanese flag echo.
                        Circle()
                            .fill(Color.white.opacity(0.06))
                            .frame(width: 220, height: 220)
                            .offset(x: 60, y: -90)
                            .blur(radius: 0.5)
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl,
                                            style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    /// Top fighters on the card to render as overlapping avatars.
    private var headlineFighters: [Athlete] {
        ["yuya_wakamatsu", "k1takeru", "nadaka", "ayaka_zombie"]
            .compactMap { h in social.athletes.first { $0.handle == h } }
    }

    /// Days / hours to fight night, presented as a tight pill.
    private var countdownPill: some View {
        let now = Date()
        let interval = Self.samuraiFightDate.timeIntervalSince(now)
        let days = Int((interval / 86_400).rounded(.down))
        let hours = Int(((interval - Double(days) * 86_400) / 3600).rounded(.down))
        let label: String
        let detail: String
        if interval < 0 {
            label = "TONIGHT"; detail = "Fight night"
        } else if days >= 1 {
            label = "\(days)"; detail = days == 1 ? "day out" : "days out"
        } else {
            label = "\(max(hours, 0))"; detail = "hours out"
        }
        return VStack(spacing: 0) {
            Text(label)
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text(detail)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.14)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Capsule().fill(.white.opacity(0.08)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
    }

    /// Camp completion bar. Reads the user's progress on the underlying
    /// "ONE Samurai 1 — Fight Week" challenge.
    private func progressStrip(_ c: Challenge) -> some View {
        let pct = max(0, min(c.currentProgress, 1.0))
        let goalLabel = "\(Int(c.goal.target)) \(c.goal.unit)"
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Fight-week camp")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.12)
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                Text("\(Int(pct * 100))% · goal \(goalLabel)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule()
                        .fill(LinearGradient(colors: [
                            Color(red: 1.00, green: 0.55, blue: 0.55),
                            Color(red: 1.00, green: 0.20, blue: 0.20),
                        ], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(pct))
                }
            }
            .frame(height: 6)
        }
    }

    // MARK: - Points card

    private var pointsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.heart.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text("Sweat")
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
            let items = filteredFeed
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                FeedCard(
                    item: item,
                    onTap: { selectedItem = item },
                    onAthleteTap: { selectedAthlete = item.athlete },
                    onKudosTap: {
                        SocialDataService.shared.toggleKudos(on: item.id)
                    },
                    onTipTap: {
                        SocialDataService.shared.sendTip(on: item.id, amount: 1)
                    },
                    onMute: {
                        SocialDataService.shared.muteAthlete(item.athlete.id)
                        Haptics.success()
                    },
                    onReport: { reportingItem = item }
                )
                // When the 3rd-from-last card appears, kick off a page
                // fetch so scrolling never hits an empty state.
                .onAppear {
                    if idx >= items.count - 3, social.hasMoreFeed {
                        Task { await social.loadMoreFeed() }
                    }
                }
            }
            if social.hasMoreFeed {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("Loading more…")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.Color.inkFaint)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
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
    let onKudosTap: () -> Void
    let onTipTap: () -> Void
    let onMute: () -> Void
    let onReport: () -> Void

    @State private var kudosBurst = false
    @State private var tipBurst = false
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.titleM)
                        .foregroundStyle(Theme.Color.ink)
                        .lineLimit(1)
                    if item.workout.verified {
                        // Small "Verified on Sui" line. Full tx digest + explorer
                        // link lives on the workout-detail view; here we just
                        // hint at the fact.
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 9, weight: .bold))
                            Text("Verified on Sui")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(Theme.Color.accentDeep)
                    }
                }
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
        HStack(spacing: 10) {
            kudosButton
            commentButton
            tipButton
            Spacer()
            shareButton
        }
    }

    private var kudosButton: some View {
        Button {
            withAnimation(Theme.Motion.bounce) { kudosBurst = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                kudosBurst = false
            }
            Haptics.pop()
            onKudosTap()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: item.userHasKudosed ? "bolt.heart.fill" : "bolt.heart")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(item.userHasKudosed ? Theme.Color.hot : Theme.Color.ink)
                    .scaleEffect(kudosBurst ? 1.35 : 1.0)
                Text("\(item.kudosCount)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(Theme.Color.ink)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Capsule().fill(Theme.Color.surface))
        }
        .buttonStyle(.plain)
    }

    /// Tappable tip — each tap adds 1 sweat and is visible as a
    /// running total on the badge. Long-press (future) will open an
    /// amount picker. Unlike kudos this is append-only — there is no
    /// un-tip.
    private var tipButton: some View {
        Button {
            withAnimation(Theme.Motion.bounce) { tipBurst = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                tipBurst = false
            }
            Haptics.tap()
            onTipTap()
        } label: {
            HStack(spacing: 5) {
                ZStack {
                    KudosCoin(size: 14)
                        .scaleEffect(tipBurst ? 1.3 : 1.0)
                    if tipBurst {
                        Text("+1")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.Color.gold)
                            .offset(y: -18)
                            .opacity(tipBurst ? 0 : 1)
                            .animation(.easeOut(duration: 0.55), value: tipBurst)
                    }
                }
                Text("\(item.tippedSweat)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .contentTransition(.numericText(value: Double(item.tippedSweat)))
            }
            .foregroundStyle(Theme.Color.gold)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(
                Capsule().fill(
                    item.tippedSweat > 0
                        ? Theme.Color.gold.opacity(0.15)
                        : Theme.Color.surface
                )
            )
            .overlay(
                Capsule().strokeBorder(
                    item.tippedSweat > 0 ? Theme.Color.gold.opacity(0.35) : .clear,
                    lineWidth: 1
                )
            )
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
            ShareSheet(items: [shareText, shareURL])
        }
    }

    /// Short workout description for the share sheet — "<name> ran 5.2 km
    /// in 32 min on SuiSport ONE" for movement activities, falls back to the
    /// feed title for sports that don't have a distance (lift, yoga…).
    private var shareText: String {
        let who = item.athlete.displayName
        let verb: String
        switch item.workout.type {
        case .run: verb = "ran"
        case .ride: verb = "rode"
        case .walk: verb = "walked"
        case .hike: verb = "hiked"
        case .swim: verb = "swam"
        default: verb = "trained"
        }
        let time = formatDuration(item.workout.duration)
        if let d = item.workout.distanceMeters, d > 0 {
            let km = String(format: "%.1f", d / 1000)
            return "\(who) \(verb) \(km) km in \(time) on SuiSport ONE"
        }
        return "\(who) \(verb) for \(time) on SuiSport ONE"
    }

    /// Deep link landing page. Backend may not have the /w/<id> route
    /// yet — a server-side 404 is fine for now; the unfurl will still
    /// carry the message copy.
    private var shareURL: URL {
        URL(string: "https://suisport.app/w/\(item.id.uuidString)")
            ?? URL(string: "https://suisport.app")!
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
