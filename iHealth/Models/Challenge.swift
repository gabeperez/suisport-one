import Foundation

struct Challenge: Identifiable, Hashable {
    var id: UUID
    var title: String
    var subtitle: String
    var kind: ChallengeKind
    var sponsor: Sponsor?
    var goal: ChallengeGoal
    var currentProgress: Double      // 0...1 — my personal progress fraction
    var startsAt: Date
    var endsAt: Date
    var stakeSweat: Int              // 0 = free; >0 = stake-to-join
    var prizePoolSweat: Int          // total pot
    var participants: Int
    var isJoined: Bool
    var hero: AvatarTone
    var badgeIcon: String            // SF Symbol
    /// Handle of the ONE fighter who designed this camp, e.g.
    /// "yuya_wakamatsu". Resolves to an Athlete via
    /// SocialDataService.athletes for the back-link from
    /// ChallengeDetailView → fighter profile and the forward-link
    /// from AthleteProfileView → "this fighter's camps."
    var designerHandle: String? = nil
    /// Headline of the trophy a participant mints on completion.
    /// e.g. "Yuya Pressure Camp Trophy". Soulbound to the user's
    /// UserProfile object on Sui.
    var trophyTitle: String? = nil
    /// User's current rank on the camp leaderboard (1-indexed). nil
    /// when we don't have a rank yet (haven't joined / no progress).
    var myRank: Int? = nil
}

enum ChallengeKind: String, Hashable, Codable {
    case distance       // run N km total
    case streak         // log X workouts in a row
    case elevation      // climb Y meters
    case workouts       // complete N workouts
    case segment        // beat a segment time
}

struct ChallengeGoal: Hashable, Codable {
    var kind: ChallengeKind
    var target: Double               // km / meters / count
    var unit: String                 // "km", "workouts", "days", "m"
}

struct Sponsor: Hashable, Codable {
    var name: String                 // e.g., "Nike", "Strava Labs"
    var handle: String               // @nike
    var color: String                // hex
}
