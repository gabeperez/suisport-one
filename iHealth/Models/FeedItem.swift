import Foundation

/// A workout as seen in a social feed — wraps a `Workout` with an owner,
/// title, description, kudos, and comments. The raw `Workout` is the
/// authoritative sensor data; the `FeedItem` is the social layer around it.
struct FeedItem: Identifiable, Hashable, Codable {
    var id: UUID
    var athlete: Athlete
    var workout: Workout
    var title: String
    var caption: String?
    var mapPreviewSeed: Int          // drives a deterministic fake map shape
    var kudos: [Kudos]
    var comments: [Comment]
    var userHasKudosed: Bool
    var tippedSweat: Int             // total $SWEAT tipped via kudos
    var taggedAthleteIDs: [String]

    var kudosCount: Int { kudos.count }
    var commentCount: Int { comments.count }
}

struct Kudos: Identifiable, Hashable, Codable {
    var id: UUID
    var athlete: Athlete
    var amountSweat: Int             // 0 = plain kudos; >0 = tipped kudos
    var at: Date
}

struct Comment: Identifiable, Hashable, Codable {
    var id: UUID
    var athlete: Athlete
    var body: String
    var at: Date
    var reactions: [String: Int]     // emoji → count
}
