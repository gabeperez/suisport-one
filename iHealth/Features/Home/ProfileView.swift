import SwiftUI

struct ProfileView: View {
    @Environment(AppState.self) private var app
    @Environment(SocialDataService.self) private var social
    @State private var showAdvanced = false
    @State private var showEdit = false
    @State private var showShare = false
    @State private var showAddShoe = false
    @State private var showRewards = false
    @State private var pendingComingSoon: ComingSoonKind?
    @State private var selectedTrophy: Trophy?
    @State private var selectedAthleteId: String?
    @State private var sweatBalance: String?
    @State private var showLogoutConfirm = false

    enum ComingSoonKind: String, Identifiable {
        case cashout, appleHealth, privacy
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Space.md) {
                    hero
                    redeemChip
                    quickStats
                    showcase
                    streakRow
                    lifetime
                    activityChart
                    personalRecords
                    gearSection
                    trophyPreview
                    clubsJoined
                    menu
                    Color.clear.frame(height: 120)
                }
                .padding(.horizontal, Theme.Space.md)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.Color.bg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showShare = true
                        } label: { Label("Share profile", systemImage: "square.and.arrow.up") }
                        Button { showRewards = true } label: {
                            Label("Redeem Sweat", systemImage: "gift.fill")
                        }
                        Button { showAdvanced = true } label: {
                            Label("Advanced", systemImage: "terminal")
                        }
                        Divider()
                        Button(role: .destructive) {
                            showLogoutConfirm = true
                        } label: {
                            Label("Log out",
                                  systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
            }
            .sheet(isPresented: $showAdvanced) { AdvancedSheet() }
            .sheet(isPresented: $showEdit) { EditProfileSheet() }
            .sheet(isPresented: $showAddShoe) { AddShoeSheet() }
            .sheet(isPresented: $showRewards) { RewardsView() }
            .sheet(isPresented: $showShare) {
                ShareSheet(items: [shareText])
            }
            .sheet(item: $pendingComingSoon) { kind in
                switch kind {
                case .cashout:
                    ComingSoonSheet(icon: "arrow.up.right.square.fill",
                                    title: "Cash out to wallet",
                                    message: "Move your Sweat to the companion wallet for swaps and gifting. We're polishing the last bits.")
                case .appleHealth:
                    ComingSoonSheet(icon: "heart.fill",
                                    title: "Apple Health",
                                    message: "Re-authorize or tweak which workout types we read. Open Settings → Privacy & Security → Health → SuiSport ONE.")
                case .privacy:
                    ComingSoonSheet(icon: "lock.fill",
                                    title: "Privacy",
                                    message: "Control who sees your workouts, map traces, and leaderboard entries. Per-activity privacy is in the roadmap.")
                }
            }
            .alert("Log out?", isPresented: $showLogoutConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Log out", role: .destructive) {
                    app.signOut()
                }
            } message: {
                Text("You'll need to sign back in to see your workouts and Sweat.")
            }
            .sheet(item: $selectedTrophy) { t in
                TrophyDetailSheet(trophy: t)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(Theme.Radius.xl)
            }
            .navigationDestination(item: Binding(
                get: { selectedAthleteId.map(AthleteRoute.init) },
                set: { selectedAthleteId = $0?.id }
            )) { route in
                AthleteProfileView(athleteId: route.id)
            }
            .task { await loadSweatBalance() }
            .refreshable {
                // Pull-to-refresh the on-chain Sweat balance after
                // submitting a workout so the pill ticks up to match
                // what's now in the user's Sui wallet.
                await loadSweatBalance()
            }
        }
    }

    private var suinsNameForMe: String? {
        social.me?.suinsName ?? app.currentUser?.suinsName
    }

    private func loadSweatBalance() async {
        guard let addr = app.currentUser?.suiAddress, addr.hasPrefix("0x"),
              addr.count == 66
        else { return }
        if let resp = try? await APIClient.shared.fetchSweatBalance(address: addr) {
            // Hide if zero so the pill doesn't clutter the hero for new users.
            sweatBalance = resp.raw == "0" ? nil : resp.display
        }
    }

    // MARK: - Hero

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            bannerBackground
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))

            // Edit / Share pills top-right
            VStack {
                HStack {
                    Spacer()
                    HStack(spacing: 6) {
                        chromePill(icon: "square.and.arrow.up") { showShare = true }
                        chromePill(icon: "pencil") { showEdit = true }
                    }
                }
                Spacer()
            }
            .padding(Theme.Space.md)

            // Avatar + name + tier
            HStack(alignment: .bottom, spacing: 14) {
                avatarBubble.shadow(color: .black.opacity(0.35), radius: 18, y: 8)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(social.me?.displayName ?? app.currentUser?.displayName ?? "You")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        if social.me?.verified == true {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    HStack(spacing: 6) {
                        if let suins = suinsNameForMe {
                            SuiNSPill(name: suins)
                        } else if let me = social.me {
                            Text("@\(me.handle)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.75))
                        }
                        if let bal = sweatBalance,
                           let addr = app.currentUser?.suiAddress,
                           let url = URL(string: "https://suiscan.xyz/testnet/account/\(addr)") {
                            Link(destination: url) {
                                SweatPill(display: bal)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens your wallet on Suiscan")
                        }
                        if let me = social.me {
                            Text("·").foregroundStyle(.white.opacity(0.5))
                            HStack(spacing: 4) {
                                Circle().fill(me.tier.ring).frame(width: 6, height: 6)
                                Text(me.tier.title)
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                }
                Spacer()
            }
            .padding(.horizontal, Theme.Space.md)
            .padding(.bottom, Theme.Space.md)
        }
        .overlay(alignment: .bottomTrailing) {
            if let loc = social.me?.location, !loc.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text(loc)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(.black.opacity(0.28)))
                .padding(Theme.Space.md)
            }
        }
    }

    private var bannerBackground: some View {
        let tone = social.me?.bannerTone ?? .sunset
        return ZStack {
            tone.gradient
            // soft spotlight for readable text
            LinearGradient(colors: [.black.opacity(0.0), .black.opacity(0.45)],
                           startPoint: .top, endPoint: .bottom)
            // subtle dotted grid as a "sport" motif
            GeometryReader { geo in
                Path { p in
                    let step: CGFloat = 22
                    var x: CGFloat = -step
                    while x < geo.size.width + step {
                        var y: CGFloat = 0
                        while y < geo.size.height {
                            p.addEllipse(in: CGRect(x: x, y: y, width: 2, height: 2))
                            y += step
                        }
                        x += step
                    }
                }
                .fill(.white.opacity(0.06))
            }
        }
    }

    private var avatarBubble: some View {
        let size: CGFloat = 84
        return ZStack {
            if let data = social.me?.photoData,
               let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 3))
            } else if let me = social.me {
                AthleteAvatar(athlete: me, size: size, showsTierRing: false)
                    .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 3))
            } else {
                Circle().fill(Theme.Color.bgElevated).frame(width: size, height: size)
            }
            // goal badge at bottom-right
            if let goal = app.currentUser?.goal {
                Circle()
                    .fill(Theme.Color.accent)
                    .frame(width: 26, height: 26)
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
                    .overlay(
                        Image(systemName: goal.icon)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.Color.accentInk)
                    )
                    .offset(x: 30, y: 30)
            }
        }
    }

    private func chromePill(icon: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap(); action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(.black.opacity(0.35)))
                .overlay(Circle().strokeBorder(.white.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Redeem chip
    // Surfaces the Rewards sheet the moment a user earns a point — a
    // Menu-only entry point left too many first-time users wondering what
    // their points were for.
    @ViewBuilder
    private var redeemChip: some View {
        if app.sweatPoints.total > 0 {
            Button {
                Haptics.tap()
                showRewards = true
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 1.00, green: 0.80, blue: 0.25),
                                             Color(red: 0.95, green: 0.55, blue: 0.15)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 36, height: 36)
                        Image(systemName: "gift.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Redeem \(app.sweatPoints.total) Sweat")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.Color.ink)
                        Text("Turn it into gear, gift cards, or featured ticket drops.")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.Color.inkSoft)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.Color.inkFaint)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .fill(Theme.Color.bgElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .strokeBorder(
                            Color(red: 0.95, green: 0.55, blue: 0.15).opacity(0.35),
                            lineWidth: 1
                        )
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Quick stats

    private var quickStats: some View {
        VStack(spacing: 10) {
            // Row 1: workouts, points, lifetime sweat
            HStack(spacing: 10) {
                statPill(value: "\(app.workouts.count)", label: "Workouts")
                statPill(value: "\(app.sweatPoints.total)", label: "Sweat")
                statPill(value: String(format: "%.1f km", totalKm),
                         label: "Lifetime")
            }
            // Row 2: followers/following/kudos
            HStack(spacing: 10) {
                statPill(value: "\(social.me?.followers ?? 0)", label: "Followers")
                statPill(value: "\(social.me?.following ?? 0)", label: "Following")
                statPill(value: "\(kudosReceived)", label: "Kudos")
            }
        }
    }

    private func statPill(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.Color.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .fill(Theme.Color.bgElevated))
    }

    // MARK: - Showcase

    private var showcase: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Showcase")
                    .font(.titleM).foregroundStyle(Theme.Color.ink)
                Spacer()
                Button {
                    Haptics.tap(); showEdit = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .bold))
                        Text("Edit")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(Theme.Color.inkSoft)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { idx in
                    showcaseSlot(index: idx)
                }
            }
        }
        .padding(Theme.Space.md)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                        .fill(Theme.Color.bgElevated))
    }

    private func showcaseSlot(index: Int) -> some View {
        let ids = social.me?.showcasedTrophyIDs ?? []
        let trophy: Trophy? = ids.indices.contains(index)
            ? social.trophies.first(where: { $0.id == ids[index] })
            : nil
        return Button {
            if let t = trophy { selectedTrophy = t }
            else { showEdit = true }
        } label: {
            if let t = trophy {
                VStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(colors: t.gradient.isEmpty
                                               ? [Theme.Color.accent, Theme.Color.accentDeep]
                                               : t.gradient,
                                               startPoint: .topLeading,
                                               endPoint: .bottomTrailing)
                            )
                            .frame(height: 100)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(t.rarity.tint.opacity(0.45), lineWidth: 2)
                            )
                        Image(systemName: t.icon)
                            .font(.system(size: 38, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                    }
                    Text(t.title)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Color.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            } else {
                VStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Theme.Color.stroke, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                            .frame(height: 100)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Theme.Color.surface.opacity(0.5))
                            )
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Theme.Color.inkFaint)
                    }
                    Text("Pin a flex")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.Color.inkFaint)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Streak

    private var streakRow: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(Theme.Color.hot.opacity(0.14))
                    .frame(width: 52, height: 52)
                Image(systemName: "flame.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.Color.hot)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(social.streak.currentDays)-day streak")
                    .font(.titleM).foregroundStyle(Theme.Color.ink)
                Text("Weekly streak · \(social.streak.weeklyStreakWeeks) weeks")
                    .font(.bodyS).foregroundStyle(Theme.Color.inkSoft)
            }
            Spacer()
            Text(String(format: "x%.2f", social.streak.multiplier))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Color.ink)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(Theme.Color.accent.opacity(0.18)))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.md).fill(Theme.Color.bgElevated))
    }

    // MARK: - Lifetime

    private var lifetime: some View {
        let t = social.lifetime(from: app.workouts)
        let cols = [GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)]
        return VStack(alignment: .leading, spacing: 12) {
            Text("Lifetime")
                .font(.titleM).foregroundStyle(Theme.Color.ink)
            LazyVGrid(columns: cols, spacing: 10) {
                lifetimeCell(label: "Running", value: Self.km(t.runMeters),
                             icon: "figure.run", tint: Theme.Color.accent)
                lifetimeCell(label: "Cycling", value: Self.km(t.rideMeters),
                             icon: "figure.outdoor.cycle", tint: Theme.Color.sky)
                lifetimeCell(label: "Walking", value: Self.km(t.walkMeters),
                             icon: "figure.walk", tint: Theme.Color.gold)
                lifetimeCell(label: "Time",
                             value: Self.hours(t.seconds),
                             icon: "stopwatch.fill", tint: Theme.Color.violet)
            }
        }
        .padding(Theme.Space.md)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                        .fill(Theme.Color.bgElevated))
    }

    private func lifetimeCell(label: String, value: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.18))
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Color.ink)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.Color.inkSoft)
            }
            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.Color.surface))
    }

    // MARK: - Activity chart (last 4 weeks by workout count)

    private var activityChart: some View {
        let weeks = Self.lastFourWeeksWorkoutCounts(from: app.workouts)
        let maxCount = max(1, weeks.map(\.count).max() ?? 1)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Last 4 weeks")
                    .font(.titleM).foregroundStyle(Theme.Color.ink)
                Spacer()
                Text("\(weeks.reduce(0) { $0 + $1.count }) workouts")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.Color.inkSoft)
            }
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(weeks, id: \.label) { w in
                    VStack(spacing: 6) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(
                                LinearGradient(colors: [Theme.Color.accent, Theme.Color.accentDeep],
                                               startPoint: .top, endPoint: .bottom)
                            )
                            .frame(height: max(6, CGFloat(w.count) / CGFloat(maxCount) * 96))
                        Text("\(w.count)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.Color.ink)
                        Text(w.label)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.Color.inkSoft)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 140, alignment: .bottom)
                }
            }
        }
        .padding(Theme.Space.md)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                        .fill(Theme.Color.bgElevated))
    }

    // MARK: - PRs

    private var personalRecords: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Personal records")
                    .font(.titleM).foregroundStyle(Theme.Color.ink)
                Spacer()
                Text("Run")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.Color.inkFaint)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Theme.Color.surface))
            }
            HStack(spacing: 8) {
                ForEach(social.personalRecords) { pr in
                    prCell(pr)
                }
            }
        }
        .padding(Theme.Space.md)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                        .fill(Theme.Color.bgElevated))
    }

    private func prCell(_ pr: PersonalRecord) -> some View {
        VStack(spacing: 4) {
            Text(pr.label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(pr.bestTimeSeconds == nil ? Theme.Color.inkFaint : Theme.Color.accentDeep)
            Text(pr.formattedTime)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Color.ink)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12)
                        .fill(pr.bestTimeSeconds == nil ? Theme.Color.surface : Theme.Color.accent.opacity(0.12)))
    }

    // MARK: - Gear

    private var gearSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Gear")
                    .font(.titleM).foregroundStyle(Theme.Color.ink)
                Spacer()
                Button { Haptics.tap(); showAddShoe = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                        Text("Add").font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(Theme.Color.inkSoft)
                }.buttonStyle(.plain)
            }
            ForEach(social.shoes.filter { !$0.retired }) { shoe in
                ShoeRow(shoe: shoe)
            }
            if social.shoes.filter({ !$0.retired }).isEmpty {
                Text("Tag shoes in a workout and they'll show up here.")
                    .font(.bodyS).foregroundStyle(Theme.Color.inkFaint)
                    .padding(.vertical, 10)
            }
        }
        .padding(Theme.Space.md)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                        .fill(Theme.Color.bgElevated))
    }

    // MARK: - Trophy preview

    @ViewBuilder
    private var trophyPreview: some View {
        if !social.trophies.isEmpty {
            NavigationLink { TrophyCaseView() } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Trophies")
                            .font(.titleM).foregroundStyle(Theme.Color.ink)
                        Spacer()
                        Text("\(social.trophies.filter { !$0.isLocked }.count) / \(social.trophies.count)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.Color.inkSoft)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.Color.inkFaint)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(social.trophies.prefix(10)) { t in
                                TrophyChip(trophy: t).frame(width: 80)
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

    // MARK: - Clubs joined

    @ViewBuilder
    private var clubsJoined: some View {
        let joined = social.clubs.filter { $0.isJoined }
        if !joined.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Clubs")
                    .font(.titleM).foregroundStyle(Theme.Color.ink)
                ForEach(joined) { club in
                    ClubRow(club: club)
                }
            }
            .padding(Theme.Space.md)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.lg).fill(Theme.Color.bgElevated))
        }
    }

    // MARK: - Menu

    private var menu: some View {
        VStack(spacing: 0) {
            demoToggleRow
            Divider().padding(.leading, 52)
            menuRow("Reset to demo data", icon: "arrow.counterclockwise") {
                resetToDemoData()
            }
            Divider().padding(.leading, 52)
            menuRow("Cash out to wallet", icon: "arrow.up.right.square.fill") {
                pendingComingSoon = .cashout
            }
            Divider().padding(.leading, 52)
            menuRow("Notifications", icon: "bell.fill") {
                openNotificationSettings()
            }
            Divider().padding(.leading, 52)
            menuRow("Apple Health", icon: "heart.fill") {
                pendingComingSoon = .appleHealth
            }
            Divider().padding(.leading, 52)
            menuRow("Privacy", icon: "lock.fill") {
                pendingComingSoon = .privacy
            }
            Divider().padding(.leading, 52)
            menuRow("Advanced", icon: "terminal.fill") { showAdvanced = true }
        }
        .background(RoundedRectangle(cornerRadius: Theme.Radius.md).fill(Theme.Color.bgElevated))
    }

    /// Stage-demo backup: when ON, the feed and clubs stay populated
    /// from local fixtures instead of being replaced by server data
    /// on refresh. Persists across launches via AppPersistence.
    private var demoToggleRow: some View {
        @Bindable var bindable = app
        return HStack(spacing: 14) {
            Image(systemName: "theatermasks.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.Color.inkSoft)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text("Show demo data")
                    .font(.bodyL)
                    .foregroundStyle(Theme.Color.ink)
                Text("Keep seeded social fixtures visible. Real actions still go through.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Color.inkFaint)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $bindable.showDemoData)
                .labelsHidden()
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, 12)
    }

    private func resetToDemoData() {
        SocialDataService.shared.reset()
        SocialDataService.shared.seed(for: app.currentUser, workouts: app.workouts)
        Haptics.success()
    }

    /// Deep-links to iOS Settings → SuiSport where the user can manage push
    /// auth, badges, and sound. Push is actually wired now — there's no
    /// in-app toggle to show.
    private func openNotificationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private var shareText: String {
        let me = social.me
        let name = me?.displayName ?? app.currentUser?.displayName ?? "me"
        let handle = me.map { "@\($0.handle)" } ?? ""
        return "Follow \(name) \(handle) on SuiSport ONE — proof-of-sweat fitness on Sui. suisport.app"
    }

    private func menuRow(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap(); action()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Color.inkSoft)
                    .frame(width: 24)
                Text(title)
                    .font(.bodyL)
                    .foregroundStyle(Theme.Color.ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Color.inkFaint)
            }
            .padding(.horizontal, Theme.Space.md)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Derived

    private var totalKm: Double {
        app.workouts.reduce(0.0) { $0 + ($1.distanceMeters ?? 0) / 1000 }
    }

    private var kudosReceived: Int {
        social.feed.filter { $0.athlete.id == social.me?.id }.reduce(0) { $0 + $1.kudosCount }
    }

    static func km(_ meters: Double) -> String {
        String(format: "%.1f km", meters / 1000)
    }
    static func hours(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        if h == 0 { return "\(m)m" }
        return "\(h)h \(m)m"
    }

    static func lastFourWeeksWorkoutCounts(from workouts: [Workout]) -> [(label: String, count: Int)] {
        let now = Date()
        let cal = Calendar.current
        var buckets: [(label: String, count: Int)] = []
        for weeksBack in (0..<4).reversed() {
            guard let end = cal.date(byAdding: .day, value: -weeksBack * 7, to: now),
                  let start = cal.date(byAdding: .day, value: -7, to: end)
            else { continue }
            let count = workouts.filter { $0.startDate >= start && $0.startDate < end }.count
            let label: String = weeksBack == 0 ? "this" : "\(weeksBack)w"
            buckets.append((label, count))
        }
        return buckets
    }
}

// MARK: - Shoe row

struct ShoeRow: View {
    let shoe: Shoe

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(shoe.tone.gradient)
                    .frame(width: 52, height: 52)
                Image(systemName: "shoe.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.2), radius: 3)
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text("\(shoe.brand) \(shoe.model)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Color.ink)
                        .lineLimit(1)
                    if shoe.isTired {
                        Text("Worn")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Capsule().fill(Theme.Color.hot))
                    }
                }
                if let nick = shoe.nickname {
                    Text(nick)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Color.inkFaint)
                }
                HStack(spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Theme.Color.stroke.opacity(0.3))
                            Capsule()
                                .fill(shoe.isTired ? Theme.Color.hot : Theme.Color.accent)
                                .frame(width: max(6, geo.size.width * CGFloat(shoe.fraction)))
                        }
                    }
                    .frame(height: 6)
                    Text("\(Int(shoe.milesUsed))/\(Int(shoe.milesTotal)) km")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.Color.inkSoft)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.Color.surface))
    }
}

// MARK: - Navigation helper

private struct AthleteRoute: Hashable { let id: String }

// MARK: - Advanced sheet

struct AdvancedSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var status: SuiStatusResponse?
    @State private var balance: SweatBalanceResponse?
    @State private var whoami: WhoamiResponse?

    var body: some View {
        NavigationStack {
            List {
                Section("Your SuiSport ONE ID") {
                    HStack {
                        Text(truncated)
                            .font(.labelMono)
                            .foregroundStyle(Theme.Color.ink)
                        Spacer()
                        Button {
                            if let addr = app.currentUser?.suiAddress {
                                UIPasteboard.general.string = addr
                                Haptics.success()
                            }
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                                .labelStyle(.iconOnly)
                        }
                    }
                    if let b = balance {
                        HStack {
                            Label("Sweat balance", systemImage: "bolt.heart.fill")
                            Spacer()
                            Text(b.display)
                                .font(.system(.body, design: .monospaced).weight(.semibold))
                        }
                    }
                }
                Section("Network") {
                    HStack {
                        Label("Network", systemImage: "network")
                        Spacer()
                        Text(status?.network ?? "—").foregroundStyle(Theme.Color.inkSoft)
                    }
                    HStack {
                        Label("On-chain pipeline", systemImage: status?.configured == true
                              ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        Spacer()
                        Text(status?.configured == true ? "Live" : "Not configured")
                            .foregroundStyle(status?.configured == true
                                             ? Theme.Color.accentDeep : Theme.Color.hot)
                    }
                    if let pkg = status?.packageId {
                        HStack {
                            Label("Package", systemImage: "shippingbox.fill")
                            Spacer()
                            Text(Self.shortenAddress(pkg))
                                .font(.labelMono)
                                .foregroundStyle(Theme.Color.inkSoft)
                        }
                    }
                    if let epoch = status?.epoch {
                        HStack {
                            Label("Epoch", systemImage: "clock")
                            Spacer()
                            Text(epoch).foregroundStyle(Theme.Color.inkSoft)
                        }
                    }
                    if let url = status.flatMap({ URL(string: "\($0.explorerUrl)/account/\(app.currentUser?.suiAddress ?? "")") }) {
                        Link(destination: url) {
                            Label("View account on Sui", systemImage: "safari")
                        }
                    } else {
                        Label("View on Sui explorer", systemImage: "safari")
                            .foregroundStyle(Theme.Color.inkFaint)
                    }
                }
                authDiagnosticsSection
                Section {
                    Text("Most people never need this page. It's here if you do.")
                        .font(.footnote)
                        .foregroundStyle(Theme.Color.inkFaint)
                }
            }
            .navigationTitle("Advanced")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await loadOnChain() }
        }
    }

    private func loadOnChain() async {
        // Read the current user off the MainActor up front so the async
        // closures below don't need to hop back for the property access.
        let addr = app.currentUser?.suiAddress
        async let s = try? await APIClient.shared.fetchSuiStatus()
        async let w = try? await APIClient.shared.fetchWhoami()
        status = await s
        whoami = await w
        if let addr {
            balance = try? await APIClient.shared.fetchSweatBalance(address: addr)
        }
    }

    @ViewBuilder
    private var authDiagnosticsSection: some View {
        Section("Auth") {
            if let w = whoami {
                HStack {
                    Label(w.authenticated ? "Signed in" : "Anonymous",
                          systemImage: w.authenticated ? "checkmark.seal.fill" : "questionmark.circle")
                    Spacer()
                    if let p = w.provider {
                        Text(p.capitalized).foregroundStyle(Theme.Color.inkSoft)
                    }
                }
                HStack {
                    Label(w.addressShape == "sui_valid"
                          ? "zkLogin address (Enoki-verified)"
                          : "Mock address (Enoki not reached)",
                          systemImage: w.addressShape == "sui_valid"
                              ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    Spacer()
                    Text(w.enokiConfigured ? "Enoki on" : "Enoki off")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(w.enokiConfigured
                                         ? Theme.Color.accentDeep : Theme.Color.hot)
                }
                if let suins = w.suinsName {
                    HStack {
                        Label("SuiNS", systemImage: "checkmark.seal.fill")
                        Spacer()
                        Text(suins).foregroundStyle(Theme.Color.accentDeep)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("No SuiNS on this address", systemImage: "minus.circle")
                            .foregroundStyle(Theme.Color.inkSoft)
                        Text("zkLogin generates a fresh Sui address per OAuth identity. Your personal wallet's SuiNS name isn't tied to it unless you register one here too.")
                            .font(.caption2)
                            .foregroundStyle(Theme.Color.inkFaint)
                    }
                }
                Button {
                    Task { whoami = try? await APIClient.shared.fetchWhoami() }
                } label: {
                    Label("Re-check identity", systemImage: "arrow.triangle.2.circlepath")
                }
            } else {
                HStack {
                    ProgressView().scaleEffect(0.7)
                    Text("Loading identity…").foregroundStyle(Theme.Color.inkSoft)
                }
            }
        }
    }

    private static func shortenAddress(_ addr: String) -> String {
        guard addr.count > 14 else { return addr }
        return "\(addr.prefix(10))…\(addr.suffix(4))"
    }

    private var truncated: String {
        let addr = app.currentUser?.suiAddress ?? "0x—"
        guard addr.count > 14 else { return addr }
        let start = addr.prefix(10)
        let end = addr.suffix(6)
        return "\(start)…\(end)"
    }
}
