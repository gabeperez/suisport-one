import SwiftUI

struct ChallengeDetailView: View {
    let challengeId: UUID
    @Environment(SocialDataService.self) private var social
    @State private var confirmJoin = false
    @State private var selectedAthlete: Athlete?

    private var challenge: Challenge? {
        social.challenges.first(where: { $0.id == challengeId })
    }

    /// Resolves the camp's designer (a registered ONE fighter) by
    /// matching `Challenge.designerHandle` against the seeded
    /// athlete roster. nil for camps with no designer (Roadwork
    /// Streak, ONE Samurai Fight Week — those are league-level).
    private var designer: Athlete? {
        guard let h = challenge?.designerHandle else { return nil }
        return social.athletes.first { $0.handle == h }
    }

    var body: some View {
        ScrollView {
            if let c = challenge {
                VStack(spacing: Theme.Space.md) {
                    hero(c)
                    designerStrip(c)
                    stakeBanner(c)
                    progress(c)
                    trainingPlan(c)
                    trophyPreview(c)
                    rewards(c)
                    leaders(c)
                    Color.clear.frame(height: 120)
                }
                .padding(.horizontal, Theme.Space.md)
            } else {
                Text("Challenge not found").padding()
            }
        }
        .background(Theme.Color.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedAthlete) { a in
            AthleteProfileView(athleteId: a.id)
        }
        .safeAreaInset(edge: .bottom) {
            if let c = challenge { bottomCTA(c) }
        }
        .alert("Stake to join", isPresented: $confirmJoin, presenting: challenge) { c in
            Button("Stake \(c.stakeSweat) Sweat") {
                SocialDataService.shared.toggleChallengeJoin(c.id)
                Haptics.success()
            }
            Button("Cancel", role: .cancel) {}
        } message: { c in
            Text("You'll stake \(c.stakeSweat) Sweat. If you complete the challenge you keep your stake and share the prize pool. If you don't, your stake goes to the pot.")
        }
    }

    // MARK: - Designer strip
    //
    // The single most demo-important link in the app: this camp was
    // designed by a real ONE fighter, and tapping the row jumps to
    // their profile. Hidden when designer is nil (league-level camps).

    @ViewBuilder
    private func designerStrip(_ c: Challenge) -> some View {
        if let d = designer {
            Button {
                Haptics.tap()
                selectedAthlete = d
            } label: {
                HStack(spacing: 12) {
                    AthleteAvatar(athlete: d, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DESIGNED BY")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .tracking(0.16)
                            .foregroundStyle(Theme.Color.inkFaint)
                        HStack(spacing: 4) {
                            Text(d.displayName)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.Color.ink)
                            if d.verified {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Theme.Color.sky)
                            }
                        }
                        if let bio = d.bio?.split(separator: ".").first {
                            Text(String(bio))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.Color.inkSoft)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.Color.inkFaint)
                }
                .padding(Theme.Space.md)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                        .fill(Theme.Color.bgElevated)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Trophy preview
    //
    // The "what you'll mint" block. Soulbound NFT on the user's Sui
    // UserProfile object; design baked from the fighter's avatar tone
    // so each camp's trophy looks distinct + named after the fighter.
    // Replaces the generic "Finisher trophy" item that used to live
    // in the Rewards block.

    @ViewBuilder
    private func trophyPreview(_ c: Challenge) -> some View {
        let title = c.trophyTitle ?? "Camp Finisher Trophy"
        let tone = (designer?.avatarTone ?? c.hero)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("What you'll earn")
                    .font(.titleM).foregroundStyle(Theme.Color.ink)
                Spacer()
                Text("VERIFIED")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(0.14)
                    .foregroundStyle(Theme.Color.gold)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(Theme.Color.gold.opacity(0.12)))
                    .overlay(Capsule().strokeBorder(Theme.Color.gold.opacity(0.4), lineWidth: 1))
            }
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(tone.gradient)
                        .frame(width: 84, height: 84)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(.white.opacity(0.25), lineWidth: 1)
                        )
                    Image(systemName: c.badgeIcon)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Color.ink)
                    if let d = designer {
                        Text("Signed by @\(d.handle) on completion")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.Color.inkSoft)
                    } else {
                        Text("Mints to your Sui UserProfile on completion")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.Color.inkSoft)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.Color.inkFaint)
                        Text("Cannot be transferred or sold")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.Color.inkFaint)
                    }
                    .padding(.top, 2)
                }
                Spacer()
            }
        }
        .padding(Theme.Space.md)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.lg).fill(Theme.Color.bgElevated))
    }

    // MARK: - Hero

    private func hero(_ c: Challenge) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let s = c.sponsor {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text("SPONSORED BY \(s.name.uppercased())")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1)
                }
                .foregroundStyle(.white.opacity(0.85))
            }
            Text(c.title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(c.subtitle)
                .font(.bodyL)
                .foregroundStyle(.white.opacity(0.85))
            HStack(spacing: 20) {
                miniStat("Participants", "\(c.participants.formatted(.number.notation(.compactName)))")
                miniStat("Ends", daysText(c))
                miniStat("Goal", "\(Int(c.goal.target)) \(c.goal.unit)")
            }
        }
        .padding(Theme.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
                .fill(c.hero.gradient)
        )
    }

    private func miniStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    // MARK: - Stake

    @ViewBuilder
    private func stakeBanner(_ c: Challenge) -> some View {
        if c.stakeSweat > 0 {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Theme.Color.gold.opacity(0.15))
                        .frame(width: 48, height: 48)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Theme.Color.gold)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Stake-to-join: \(c.stakeSweat) Sweat")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.Color.ink)
                    Text("Finish the challenge, keep your stake and split the \(c.prizePoolSweat.formatted(.number.notation(.compactName))) Sweat pot. Miss it, your stake joins the pool.")
                        .font(.bodyS)
                        .foregroundStyle(Theme.Color.inkSoft)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.md).fill(Theme.Color.bgElevated))
        }
    }

    // MARK: - Progress

    private func progress(_ c: Challenge) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Your progress")
                    .font(.titleM).foregroundStyle(Theme.Color.ink)
                Spacer()
                Text("\(Int(c.currentProgress * 100))%")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Color.ink)
            }
            ProgressBar(progress: c.currentProgress, tint: c.hero.colors.0)
                .frame(height: 12)
            Text(progressText(c))
                .font(.bodyS).foregroundStyle(Theme.Color.inkSoft)
        }
        .padding(Theme.Space.md)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.lg).fill(Theme.Color.bgElevated))
    }

    private func progressText(_ c: Challenge) -> String {
        let mine = Int(c.goal.target * c.currentProgress)
        let target = Int(c.goal.target)
        return "\(mine) of \(target) \(c.goal.unit)"
    }

    // MARK: - Training plan
    //
    // The "what you actually have to do" block. Generated from the
    // camp's designer specialty + target session count via
    // CampPlanner. Long camps (Nadaka's 30-day Lumpinee Mile) collapse
    // to a 7-row preview with a "+ N more sessions" footer so the
    // detail view stays scannable.

    private func trainingPlan(_ c: Challenge) -> some View {
        let plan = CampPlanner.plan(for: c)
        let preview = plan.prefix(7)
        let remaining = max(0, plan.count - preview.count)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Training plan")
                    .font(.titleM).foregroundStyle(Theme.Color.ink)
                Spacer()
                Text("\(plan.count) session\(plan.count == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(0.12)
                    .foregroundStyle(Theme.Color.inkFaint)
            }
            VStack(spacing: 8) {
                ForEach(Array(preview), id: \.id) { session in
                    sessionRow(session, accent: c.hero.colors.0)
                }
                if remaining > 0 {
                    Text("+ \(remaining) more session\(remaining == 1 ? "" : "s") in this camp")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.Color.inkFaint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                }
            }
        }
        .padding(Theme.Space.md)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.lg).fill(Theme.Color.bgElevated))
    }

    private func sessionRow(_ s: CampSession, accent: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 2) {
                Text("DAY")
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                    .tracking(0.14)
                    .foregroundStyle(Theme.Color.inkFaint)
                Text("\(s.dayIndex)")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.Color.ink)
            }
            .frame(width: 38)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(accent.opacity(0.14))
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: s.type.icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(accent)
                    Text(s.title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Color.ink)
                    Text("· \(s.minutes) min")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.Color.inkFaint)
                }
                Text(s.detail)
                    .font(.bodyS)
                    .foregroundStyle(Theme.Color.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Rewards

    /// Rewards beyond the trophy. Trophy lives in `trophyPreview`;
    /// this is for SWEAT pool + sponsor drops.
    private func rewards(_ c: Challenge) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Plus")
                .font(.titleM).foregroundStyle(Theme.Color.ink)
            if c.prizePoolSweat > 0 {
                reward(icon: "bolt.heart.fill",
                       title: "\(c.prizePoolSweat.formatted(.number.notation(.compactName))) Sweat pool",
                       body: "Split among finishers, weighted by completion. Minted by rewards_engine on Sui.",
                       tint: Theme.Color.hot)
            }
            if let s = c.sponsor {
                reward(icon: "gift.fill", title: "\(s.name) drop",
                       body: "Early access to limited gear for the top 10%.",
                       tint: Theme.Color.violet)
            }
        }
        .padding(Theme.Space.md)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.lg).fill(Theme.Color.bgElevated))
    }

    private func reward(icon: String, title: String, body: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.Color.ink)
                Text(body).font(.bodyS).foregroundStyle(Theme.Color.inkSoft)
            }
            Spacer()
        }
    }

    // MARK: - Leaderboard with rank

    /// "Stack up" framing — leads with the user's own rank, then the
    /// top of the leaderboard. Rank is read from `Challenge.myRank`
    /// (set on the seed; in production read from the aggregator).
    /// Mock leaderboard percentages are deterministic per athlete id
    /// so the same fighters don't get random new rankings on every
    /// re-render.
    private func leaders(_ c: Challenge) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row — your rank is the headline, total
            // participants the supporting stat.
            HStack(alignment: .firstTextBaseline) {
                Text("Stack up")
                    .font(.titleM).foregroundStyle(Theme.Color.ink)
                Spacer()
                if let r = c.myRank {
                    let percentile = max(1, Int(Double(r) / Double(max(1, c.participants)) * 100))
                    Text("Top \(percentile)%")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(0.12)
                        .foregroundStyle(Theme.Color.accentDeep)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Theme.Color.accent.opacity(0.18)))
                }
            }

            // Your rank tile.
            if c.isJoined {
                myRankTile(c)
            }

            // Top of the field — first 5.
            ForEach(Array(social.athletes.prefix(5).enumerated()), id: \.offset) { idx, a in
                HStack(spacing: 12) {
                    Text("\(idx + 1)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Color.inkFaint)
                        .frame(width: 24)
                    AthleteAvatar(athlete: a, size: 32, showsTierRing: false)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(a.displayName)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.Color.ink)
                        Text("@\(a.handle)")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Color.inkFaint)
                    }
                    Spacer()
                    Text("\(deterministicPercent(for: a, top: idx))%")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Color.ink)
                }
                .padding(.vertical, 6)
            }
        }
        .padding(Theme.Space.md)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.lg).fill(Theme.Color.bgElevated))
    }

    /// Inline tile showing the viewer's rank against the camp. Pulls
    /// the user's avatar from social.me when available.
    private func myRankTile(_ c: Challenge) -> some View {
        HStack(spacing: 12) {
            Text(c.myRank.map { "#\($0)" } ?? "—")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.Color.accentInk)
                .frame(width: 56)
                .padding(.vertical, 6)
                .background(Capsule().fill(Theme.Color.accent))
            if let me = social.me {
                AthleteAvatar(athlete: me, size: 32, showsTierRing: false)
                VStack(alignment: .leading, spacing: 1) {
                    Text("You")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.Color.ink)
                    Text("of \(c.participants.formatted(.number.notation(.compactName))) training")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Color.inkFaint)
                }
            }
            Spacer()
            Text("\(Int(c.currentProgress * 100))%")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Color.ink)
        }
        .padding(.vertical, 8).padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .fill(Theme.Color.accent.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .strokeBorder(Theme.Color.accent.opacity(0.25), lineWidth: 1))
    }

    /// Deterministic 60-99% completion bucket per athlete so the
    /// leaderboard doesn't shuffle on every re-render.
    private func deterministicPercent(for a: Athlete, top idx: Int) -> Int {
        // First entry is always near-finish for the demo, then taper.
        let base = [99, 94, 88, 82, 76, 71, 64][min(idx, 6)]
        // Tiny per-athlete jitter so two cards with the same idx don't
        // read identically when the leaderboard size shifts.
        let jitter = abs(a.id.hashValue) % 4 - 2
        return min(99, max(50, base + jitter))
    }

    // MARK: - Bottom CTA

    private func bottomCTA(_ c: Challenge) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                if c.isJoined {
                    PrimaryButton(title: "Joined — keep going",
                                  icon: "checkmark",
                                  tint: Theme.Color.accent,
                                  fg: Theme.Color.accentInk) {
                        SocialDataService.shared.toggleChallengeJoin(c.id)
                    }
                } else {
                    PrimaryButton(title: c.stakeSweat > 0 ? "Stake and join" : "Join",
                                  icon: c.stakeSweat > 0 ? "lock.fill" : "plus",
                                  tint: Theme.Color.ink, fg: Theme.Color.inkInverse) {
                        if c.stakeSweat > 0 { confirmJoin = true }
                        else { SocialDataService.shared.toggleChallengeJoin(c.id) }
                    }
                }
            }
            .padding(Theme.Space.md)
        }
        .background(.ultraThinMaterial)
    }

    private func daysText(_ c: Challenge) -> String {
        let secs = c.endsAt.timeIntervalSinceNow
        guard secs > 0 else { return "Ended" }
        let d = Int(secs / 86400)
        return "\(d) day\(d == 1 ? "" : "s")"
    }
}
