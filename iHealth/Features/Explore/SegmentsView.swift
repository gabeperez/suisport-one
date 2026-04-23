import SwiftUI

struct SegmentsView: View {
    @Environment(SocialDataService.self) private var social
    @State private var selected: Segment?

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.md) {
                intro
                ForEach(social.segments) { s in
                    Button { selected = s } label: {
                        SegmentRow(segment: s)
                    }
                    .buttonStyle(.plain)
                }
                Color.clear.frame(height: 120)
            }
            .padding(.horizontal, Theme.Space.md)
            .padding(.top, Theme.Space.md)
        }
        .navigationDestination(item: $selected) { s in
            SegmentDetailView(segmentId: s.id)
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Segments near you")
                .font(.titleL).foregroundStyle(Theme.Color.ink)
            Text("Every fast lap logged on Sui. KOM and QOM are provably yours.")
                .font(.bodyM).foregroundStyle(Theme.Color.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SegmentRow: View {
    let segment: Segment

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            leaderStrip
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.lg).fill(Theme.Color.bgElevated))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(segment.heroTone.gradient)
                    .frame(width: 52, height: 52)
                Image(systemName: segment.surface.icon)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(segment.name)
                        .font(.titleM).foregroundStyle(Theme.Color.ink)
                        .lineLimit(1)
                    if segment.starred {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.Color.gold)
                    }
                }
                Text(segment.location)
                    .font(.bodyS).foregroundStyle(Theme.Color.inkSoft)
                HStack(spacing: 10) {
                    meta(icon: "ruler", "\(distString)")
                    if segment.elevationGainM > 0 {
                        meta(icon: "arrow.up.right", "\(Int(segment.elevationGainM))m")
                    }
                    if segment.avgGradePct > 0 {
                        meta(icon: "triangle.fill", String(format: "%.1f%%", segment.avgGradePct))
                    }
                }
            }
            Spacer()
        }
    }

    private var distString: String {
        let km = segment.distanceMeters / 1000
        if km >= 1 { return String(format: "%.2f km", km) }
        return "\(Int(segment.distanceMeters)) m"
    }

    private func meta(icon: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(Theme.Color.inkFaint)
    }

    private var leaderStrip: some View {
        HStack(spacing: 6) {
            if let kom = segment.kom {
                leader(title: "KOM", entry: kom, color: Theme.Color.gold)
            }
            if let qom = segment.qom {
                leader(title: "QOM", entry: qom, color: Color(red: 1.0, green: 0.4, blue: 0.7))
            }
            if let ll = segment.localLegend {
                legendPill(entry: ll)
            }
        }
    }

    private func leader(title: String, entry: LeaderboardEntry, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            AthleteAvatar(athlete: entry.athlete, size: 18, showsTierRing: false)
            Text(formatTime(entry.timeSeconds))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.Color.ink)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.14)))
    }

    private func legendPill(entry: LeaderboardEntry) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "crown.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.Color.violet)
            AthleteAvatar(athlete: entry.athlete, size: 18, showsTierRing: false)
            Text("\(entry.attempts) efforts")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.Color.ink)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Capsule().fill(Theme.Color.violet.opacity(0.14)))
    }

    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60; let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Segment detail

struct SegmentDetailView: View {
    let segmentId: UUID
    @Environment(SocialDataService.self) private var social
    @State private var board: BoardTab = .all

    enum BoardTab: String, CaseIterable {
        case all, women, localLegends
        var title: String {
            switch self {
            case .all: return "All"
            case .women: return "Women"
            case .localLegends: return "Local Legends"
            }
        }
    }

    private var segment: Segment? { social.segments.first(where: { $0.id == segmentId }) }

    var body: some View {
        ScrollView {
            if let s = segment {
                VStack(spacing: Theme.Space.md) {
                    hero(s)
                    quickStats(s)
                    champion(s)
                    boardTabs
                    leaderboard
                    Color.clear.frame(height: 80)
                }
                .padding(.horizontal, Theme.Space.md)
            } else {
                Text("Segment not found").padding()
            }
        }
        .background(Theme.Color.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let s = segment {
                    Button {
                        SocialDataService.shared.toggleSegmentStar(s.id)
                        Haptics.tap()
                    } label: {
                        Image(systemName: s.starred ? "star.fill" : "star")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(s.starred ? Theme.Color.gold : Theme.Color.ink)
                    }
                }
            }
        }
    }

    // MARK: - Hero

    private func hero(_ s: Segment) -> some View {
        ZStack(alignment: .bottomLeading) {
            FakeMapPreview(seed: abs(s.id.hashValue), tone: s.heroTone)
                .frame(height: 200)
            LinearGradient(colors: [.black.opacity(0), .black.opacity(0.6)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 200)
            VStack(alignment: .leading, spacing: 3) {
                Text(s.name)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                HStack(spacing: 6) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text(s.location)
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.85))
            }
            .padding(Theme.Space.lg)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
    }

    // MARK: - Stats

    private func quickStats(_ s: Segment) -> some View {
        HStack(spacing: 0) {
            statCell(String(format: "%.2f km", s.distanceMeters / 1000), "Distance")
            Divider().frame(height: 30).overlay(Theme.Color.stroke)
            statCell("\(Int(s.elevationGainM))m", "Climb")
            Divider().frame(height: 30).overlay(Theme.Color.stroke)
            statCell(String(format: "%.1f%%", s.avgGradePct), "Avg grade")
            Divider().frame(height: 30).overlay(Theme.Color.stroke)
            statCell("\(s.totalAttempts.formatted(.number.notation(.compactName)))", "Efforts")
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.md).fill(Theme.Color.bgElevated))
    }

    private func statCell(_ v: String, _ l: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Color.ink)
            Text(l).font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.Color.inkSoft)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Champion

    @ViewBuilder
    private func champion(_ s: Segment) -> some View {
        if let kom = s.kom {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Theme.Color.gold.opacity(0.18)).frame(width: 58, height: 58)
                    Image(systemName: "crown.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Theme.Color.gold)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("KOM · \(formatTime(kom.timeSeconds))")
                        .font(.titleM).foregroundStyle(Theme.Color.ink)
                    HStack(spacing: 6) {
                        AthleteAvatar(athlete: kom.athlete, size: 20, showsTierRing: false)
                        Text(kom.athlete.displayName)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.Color.inkSoft)
                    }
                }
                Spacer()
                PillButton(title: "Tip KOM", icon: "bolt.heart.fill",
                           tint: Theme.Color.gold, fg: Theme.Color.accentInk) {}
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.md).fill(Theme.Color.bgElevated))
        }
    }

    // MARK: - Board tabs

    private var boardTabs: some View {
        HStack(spacing: 6) {
            ForEach(BoardTab.allCases, id: \.self) { t in
                Button {
                    Haptics.select()
                    withAnimation(Theme.Motion.snap) { board = t }
                } label: {
                    Text(t.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(board == t ? Theme.Color.inkInverse : Theme.Color.ink)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Capsule().fill(board == t ? Theme.Color.ink : Theme.Color.bgElevated))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: - Leaderboard

    private var leaderboard: some View {
        VStack(spacing: 0) {
            ForEach(Array(social.athletes.prefix(10).enumerated()), id: \.offset) { idx, a in
                leaderRow(rank: idx + 1, athlete: a,
                          time: (idx + 1) * 60 + Int.random(in: 5...55))
                if idx < 9 { Divider().padding(.leading, 56) }
            }
        }
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.lg).fill(Theme.Color.bgElevated))
    }

    private func leaderRow(rank: Int, athlete: Athlete, time: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(rank <= 3 ? Theme.Color.gold : Theme.Color.inkFaint)
                .frame(width: 24)
            AthleteAvatar(athlete: athlete, size: 32, showsTierRing: false)
            VStack(alignment: .leading, spacing: 0) {
                Text(athlete.displayName)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.Color.ink)
                Text("@\(athlete.handle)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Color.inkFaint)
            }
            Spacer()
            Text(formatTime(time))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Color.ink)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60; let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
