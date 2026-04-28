import Foundation
import SwiftUI

/// A person in SuiSport — either the current user or someone they follow.
/// Abstracted from `User` because feed items / kudos / comments all reference
/// a lightweight athlete identity, not a full logged-in session.
struct Athlete: Identifiable, Hashable, Codable {
    var id: String                          // Stable server-assigned UUID (never changes)
    var suiAddress: String? = nil           // On-chain identity (present when authed via zkLogin)
    var handle: String                      // @handle, user-mutable
    var displayName: String
    var avatarTone: AvatarTone              // deterministic color for gradient avatar
    var verified: Bool                      // blue check for pro athletes / partners
    var tier: AthleteTier                   // mirrors NRC "pigment progression" — colored ring
    var totalWorkouts: Int
    var followers: Int
    var following: Int
    var bio: String?

    // Customization — drive the editable profile hero.
    var bannerTone: AvatarTone = .sunset
    var photoData: Data? = nil              // user-picked avatar; takes precedence over gradient
    /// Up to 3 pinned trophies. Stored as `Trophy.stableKey` strings
    /// (e.g. "5k-finisher") rather than UUIDs, because Trophy.id is
    /// regenerated fresh on every seed — UUIDs would silently fail
    /// to resolve across launches.
    var showcasedTrophyIDs: [String] = []
    var location: String? = nil             // optional "Brooklyn, NY"
    var suinsName: String? = nil            // "alice.sui" if the address owns one
    var pronouns: String? = nil             // "she/her", "they/them", etc.
    var websiteUrl: String? = nil           // personal site / Linktree
    /// Remote avatar URL served by the backend after a /media/avatar upload.
    /// Preferred over `photoData` when present — clients can render it
    /// async without carrying bytes around.
    var photoURL: String? = nil

    static func preview(_ handle: String, name: String, tier: AthleteTier = .starter,
                        verified: Bool = false) -> Athlete {
        let tone = AvatarTone.tone(for: handle)
        // Deterministic "UUID-like" id from the handle so SwiftUI list
        // diffing stays stable across app launches.
        let localId = "local_\(String(handle.hashValue.magnitude, radix: 16))"
        return Athlete(
            id: localId,
            suiAddress: nil,                 // offline seeds have no on-chain identity
            handle: handle,
            displayName: name,
            avatarTone: tone,
            verified: verified,
            tier: tier,
            totalWorkouts: Int.random(in: 40...600),
            followers: Int.random(in: 20...5000),
            following: Int.random(in: 30...400),
            bio: nil,
            bannerTone: AvatarTone.allCases.randomElement() ?? tone,
            photoData: nil,
            showcasedTrophyIDs: [],
            location: nil
        )
    }
}

enum AthleteTier: String, Codable, CaseIterable {
    case starter, bronze, silver, gold, legend

    var ring: Color {
        switch self {
        case .starter: return Color(.separator)
        case .bronze: return Color(red: 0.80, green: 0.55, blue: 0.30)
        case .silver: return Color(red: 0.78, green: 0.78, blue: 0.82)
        case .gold: return Color(red: 0.98, green: 0.80, blue: 0.27)
        case .legend: return Color(red: 0.55, green: 0.35, blue: 1.00)
        }
    }

    var title: String {
        switch self {
        case .starter: return "Starter"
        case .bronze: return "Bronze"
        case .silver: return "Silver"
        case .gold: return "Gold"
        case .legend: return "Legend"
        }
    }

    /// Approximate threshold in lifetime workouts for each tier.
    var threshold: Int {
        switch self {
        case .starter: return 0
        case .bronze: return 20
        case .silver: return 100
        case .gold: return 300
        case .legend: return 1000
        }
    }
}

/// Deterministic avatar tone derived from a handle, so mock athletes stay
/// visually stable across renders.
enum AvatarTone: String, Codable, CaseIterable {
    case sunset, ocean, forest, grape, ember, mint, slate, rose

    var gradient: LinearGradient {
        let (a, b) = colors
        return LinearGradient(colors: [a, b], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var colors: (Color, Color) {
        switch self {
        case .sunset: return (Color(red: 1.00, green: 0.55, blue: 0.30),
                              Color(red: 0.95, green: 0.25, blue: 0.45))
        case .ocean:  return (Color(red: 0.30, green: 0.65, blue: 0.95),
                              Color(red: 0.15, green: 0.45, blue: 0.80))
        case .forest: return (Color(red: 0.30, green: 0.80, blue: 0.48),
                              Color(red: 0.05, green: 0.50, blue: 0.30))
        case .grape:  return (Color(red: 0.55, green: 0.35, blue: 1.00),
                              Color(red: 0.35, green: 0.20, blue: 0.75))
        case .ember:  return (Color(red: 1.00, green: 0.70, blue: 0.20),
                              Color(red: 0.95, green: 0.40, blue: 0.20))
        case .mint:   return (Color(red: 0.50, green: 0.98, blue: 0.70),
                              Color(red: 0.10, green: 0.70, blue: 0.55))
        case .slate:  return (Color(red: 0.55, green: 0.60, blue: 0.68),
                              Color(red: 0.30, green: 0.35, blue: 0.42))
        case .rose:   return (Color(red: 1.00, green: 0.55, blue: 0.75),
                              Color(red: 0.80, green: 0.25, blue: 0.50))
        }
    }

    static func tone(for key: String) -> AvatarTone {
        let idx = abs(key.hashValue) % AvatarTone.allCases.count
        return AvatarTone.allCases[idx]
    }
}
