import Foundation

// Sendable lets AppPersistence encode/decode this from its
// nonisolated background queue without Swift 6 emitting a
// "main-actor-isolated conformance of User to Codable cannot be
// used in nonisolated context" warning. All stored properties are
// already Sendable (String / URL / Date / Optionals).
struct User: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var displayName: String
    var avatarURL: URL?
    var goal: UserGoal?
    /// Sui address derived from zkLogin. Never shown in UI — buried in Settings → Advanced.
    var suiAddress: String
    /// SuiNS name owned by the address (e.g. "alice.sui"), if any.
    /// Pre-fills NameGoal + shows as a pill in the profile hero.
    var suinsName: String? = nil
    /// Suggested default handle from SuiNS — "alice" from "alice.sui".
    /// NameGoal uses it as a placeholder; user can override.
    var suggestedHandle: String? = nil
    /// Set during onboarding age gate; synced to `PATCH /me` as unix seconds.
    var dateOfBirth: Date? = nil
    var createdAt: Date
}

enum AuthProvider: String, Codable, Sendable { case apple, google }

/// Onboarding goals — what the user is here for. Reframed for SuiSport
/// ONE around martial arts. Generic activity ("stay active") still
/// reachable via the cross-training case so a runner who follows ONE
/// for the fights isn't excluded.
enum UserGoal: String, CaseIterable, Codable, Identifiable, Sendable {
    case fightCamp, striking, grappling, crossTrain

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fightCamp:  return "Fight camp"
        case .striking:   return "Striking"
        case .grappling:  return "Grappling"
        case .crossTrain: return "Cross-train"
        }
    }

    /// Short hint shown under the title (or used as a tooltip) so
    /// users picking the goal know what's behind it.
    var subtitle: String {
        switch self {
        case .fightCamp:  return "Train like a fighter"
        case .striking:   return "Boxing · Muay Thai · K-1"
        case .grappling:  return "BJJ · wrestling · clinch"
        case .crossTrain: return "Run, ride, lift, recover"
        }
    }

    var icon: String {
        switch self {
        case .fightCamp:  return "figure.martial.arts"
        case .striking:   return "figure.boxing"
        case .grappling:  return "figure.wrestling"
        case .crossTrain: return "figure.cross.training"
        }
    }
}
