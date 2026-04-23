import SwiftUI

struct ChallengesView: View {
    @Environment(SocialDataService.self) private var social
    @State private var selected: Challenge?
    @State private var filter: ChallengeFilter = .active

    enum ChallengeFilter: String, CaseIterable {
        case active, joined, sponsored
        var title: String {
            switch self {
            case .active: return "All active"
            case .joined: return "Joined"
            case .sponsored: return "Sponsored"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            filterRow.padding(.horizontal, Theme.Space.md).padding(.top, 4)
            ScrollView {
                VStack(spacing: Theme.Space.md) {
                    ForEach(filteredChallenges) { c in
                        Button { selected = c } label: {
                            ChallengeCard(challenge: c)
                        }
                        .buttonStyle(.plain)
                    }
                    Color.clear.frame(height: 120)
                }
                .padding(.horizontal, Theme.Space.md)
                .padding(.top, Theme.Space.md)
            }
            .navigationDestination(item: $selected) { c in
                ChallengeDetailView(challengeId: c.id)
            }
        }
    }

    private var filterRow: some View {
        HStack(spacing: 8) {
            ForEach(ChallengeFilter.allCases, id: \.self) { f in
                Button {
                    Haptics.select()
                    withAnimation(Theme.Motion.snap) { filter = f }
                } label: {
                    Text(f.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(filter == f ? Theme.Color.inkInverse : Theme.Color.ink)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(
                            Capsule().fill(filter == f ? Theme.Color.ink : Theme.Color.bgElevated)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private var filteredChallenges: [Challenge] {
        switch filter {
        case .active: return social.challenges
        case .joined: return social.challenges.filter { $0.isJoined }
        case .sponsored: return social.challenges.filter { $0.sponsor != nil }
        }
    }
}

struct ChallengeCard: View {
    let challenge: Challenge

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(challenge.hero.gradient)
                        .frame(width: 58, height: 58)
                    Image(systemName: challenge.badgeIcon)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                }
                VStack(alignment: .leading, spacing: 4) {
                    if let s = challenge.sponsor {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text(s.name.uppercased())
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .tracking(0.7)
                        }
                        .foregroundStyle(Theme.Color.violet)
                    }
                    Text(challenge.title)
                        .font(.titleL)
                        .foregroundStyle(Theme.Color.ink)
                    Text(challenge.subtitle)
                        .font(.bodyS)
                        .foregroundStyle(Theme.Color.inkSoft)
                }
                Spacer()
                if challenge.isJoined {
                    Text("In")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Color.accentDeep)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Theme.Color.accent.opacity(0.18)))
                }
            }

            progressBlock
            meta
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.lg).fill(Theme.Color.bgElevated))
    }

    @ViewBuilder
    private var progressBlock: some View {
        if challenge.isJoined {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(progressText)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.Color.ink)
                    Spacer()
                    Text("\(Int(challenge.currentProgress * 100))%")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Color.inkSoft)
                }
                ProgressBar(progress: challenge.currentProgress, tint: challenge.hero.colors.0)
            }
        }
    }

    private var progressText: String {
        let target = Int(challenge.goal.target)
        let mine = Int(challenge.goal.target * challenge.currentProgress)
        return "\(mine) / \(target) \(challenge.goal.unit)"
    }

    private var meta: some View {
        HStack(spacing: 12) {
            pill(icon: "person.2.fill", "\(challenge.participants.formatted(.number.notation(.compactName)))")
            pill(icon: "calendar", daysLeft)
            if challenge.stakeSweat > 0 {
                pill(icon: "lock.fill", "\(challenge.stakeSweat) stake", tint: Theme.Color.gold)
            }
            if challenge.prizePoolSweat > 0 {
                pill(icon: "trophy.fill", "\(challenge.prizePoolSweat.formatted(.number.notation(.compactName))) pot",
                     tint: Theme.Color.violet)
            }
            Spacer()
        }
    }

    private func pill(icon: String, _ text: String, tint: Color? = nil) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(tint ?? Theme.Color.inkSoft)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill((tint ?? Theme.Color.ink).opacity(0.08)))
    }

    private var daysLeft: String {
        let secs = challenge.endsAt.timeIntervalSinceNow
        guard secs > 0 else { return "Ended" }
        let days = Int(secs / 86400)
        if days == 0 { return "Ends today" }
        if days == 1 { return "1 day left" }
        return "\(days) days left"
    }
}

struct ProgressBar: View {
    let progress: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.Color.stroke.opacity(0.3))
                Capsule()
                    .fill(tint)
                    .frame(width: max(8, geo.size.width * CGFloat(min(1, max(0, progress)))))
                    .animation(Theme.Motion.soft, value: progress)
            }
        }
        .frame(height: 8)
    }
}
