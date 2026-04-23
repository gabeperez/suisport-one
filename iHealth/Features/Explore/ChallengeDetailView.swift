import SwiftUI

struct ChallengeDetailView: View {
    let challengeId: UUID
    @Environment(SocialDataService.self) private var social
    @State private var confirmJoin = false

    private var challenge: Challenge? {
        social.challenges.first(where: { $0.id == challengeId })
    }

    var body: some View {
        ScrollView {
            if let c = challenge {
                VStack(spacing: Theme.Space.md) {
                    hero(c)
                    stakeBanner(c)
                    progress(c)
                    rewards(c)
                    leaders
                    Color.clear.frame(height: 120)
                }
                .padding(.horizontal, Theme.Space.md)
            } else {
                Text("Challenge not found").padding()
            }
        }
        .background(Theme.Color.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
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

    // MARK: - Rewards

    private func rewards(_ c: Challenge) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rewards")
                .font(.titleM).foregroundStyle(Theme.Color.ink)
            reward(icon: "trophy.fill", title: "Finisher trophy", body: "Soulbound NFT on your Sui profile.",
                   tint: Theme.Color.gold)
            if c.prizePoolSweat > 0 {
                reward(icon: "bolt.heart.fill",
                       title: "\(c.prizePoolSweat.formatted(.number.notation(.compactName))) Sweat pool",
                       body: "Split among finishers, weighted by completion.",
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

    // MARK: - Leaders

    private var leaders: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Leaders").font(.titleM).foregroundStyle(Theme.Color.ink)
            ForEach(Array(social.athletes.prefix(6).enumerated()), id: \.offset) { idx, a in
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
                    Text("\(Int.random(in: 42...95))%")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Color.ink)
                }
                .padding(.vertical, 6)
            }
        }
        .padding(Theme.Space.md)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.lg).fill(Theme.Color.bgElevated))
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
