import Foundation

struct Club: Identifiable, Hashable {
    var id: UUID
    var name: String
    var handle: String               // @club_handle
    var tagline: String
    var description: String
    var heroTone: AvatarTone
    var memberCount: Int
    var sweatTreasury: Int           // club DAO treasury in $SWEAT
    var isJoined: Bool
    var isVerifiedBrand: Bool        // a brand-run club (Rapha, Nike, etc.)
    var weeklyKm: Double             // aggregate distance this week
    var tags: [String]               // ["running", "sub-3", "NYC"]
    var activeChallengeIDs: [UUID]
}
