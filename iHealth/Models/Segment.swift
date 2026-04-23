import Foundation

struct Segment: Identifiable, Hashable {
    var id: UUID
    var name: String
    var location: String             // "Brooklyn, NY"
    var distanceMeters: Double
    var elevationGainM: Double
    var avgGradePct: Double
    var totalAttempts: Int
    var athleteCount: Int
    var kom: LeaderboardEntry?       // fastest man
    var qom: LeaderboardEntry?       // fastest woman
    var localLegend: LeaderboardEntry?   // most attempts in last 90 days
    var myBest: LeaderboardEntry?
    var myRank: Int?
    var starred: Bool
    var surface: SegmentSurface
    var heroTone: AvatarTone
}

enum SegmentSurface: String, Codable, Hashable {
    case road, trail, gravel, mixed
    var title: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .road: return "road.lanes"
        case .trail: return "mountain.2.fill"
        case .gravel: return "circle.dotted"
        case .mixed: return "map.fill"
        }
    }
}

struct LeaderboardEntry: Identifiable, Hashable {
    var id: UUID
    var athlete: Athlete
    var timeSeconds: Int             // for KOM/QOM
    var attempts: Int                // for Local Legend
    var achievedAt: Date
}
