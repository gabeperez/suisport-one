import Foundation

struct User: Identifiable, Hashable, Codable {
    var id: String
    var displayName: String
    var avatarURL: URL?
    var goal: UserGoal?
    /// Sui address derived from zkLogin. Never shown in UI — buried in Settings → Advanced.
    var suiAddress: String
    var createdAt: Date
}

enum AuthProvider: String, Codable { case apple, google }

enum UserGoal: String, CaseIterable, Codable, Identifiable {
    case run, ride, lift, justMove

    var id: String { rawValue }

    var title: String {
        switch self {
        case .run: return "Run"
        case .ride: return "Ride"
        case .lift: return "Lift"
        case .justMove: return "Just move"
        }
    }

    var icon: String {
        switch self {
        case .run: return "figure.run"
        case .ride: return "figure.outdoor.cycle"
        case .lift: return "figure.strengthtraining.traditional"
        case .justMove: return "figure.walk.motion"
        }
    }
}
