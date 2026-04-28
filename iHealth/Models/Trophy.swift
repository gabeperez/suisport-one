import Foundation
import SwiftUI

/// Achievement / trophy. Soulbound in the Move package — portable across
/// fitness apps, flex-able on any chain viewer.
struct Trophy: Identifiable, Hashable {
    var id: UUID
    /// Stable string key so we can persist "the user claimed this
    /// trophy" across app launches. The `id` is a fresh UUID per
    /// seed, so it can't be used for that.
    var stableKey: String
    var title: String
    var subtitle: String
    var icon: String                 // SF Symbol
    var rarity: Rarity
    var earnedAt: Date?              // nil if locked or claimable
    var progress: Double             // 0...1 toward unlocking
    var category: TrophyCategory
    var gradient: [Color]            // cosmetic — a two-stop gradient
    /// When the trophy criterion is met by an existing workout, this
    /// is that workout's id. Tapping "Claim trophy" mints the workout
    /// (if it isn't on chain yet) and then marks this trophy as
    /// earned. nil means there's no qualifying workout yet — the
    /// trophy is truly locked, not just unclaimed.
    var qualifyingWorkoutId: UUID? = nil

    /// True when there is no path to unlock yet — keep the gray
    /// medallion treatment for these.
    var isLocked: Bool { earnedAt == nil && qualifyingWorkoutId == nil }
    /// True when the user has done the qualifying work but hasn't
    /// pressed Claim yet. Renders with full color + a Claim badge.
    var isClaimable: Bool { earnedAt == nil && qualifyingWorkoutId != nil }
    /// True once claimed — full color medallion + checkmark + date.
    var isUnlocked: Bool { earnedAt != nil }
}

enum Rarity: String, Codable, Hashable {
    case common, rare, epic, legendary

    var title: String { rawValue.capitalized }

    var tint: Color {
        switch self {
        case .common: return Color(.systemGray)
        case .rare: return Color(red: 0.27, green: 0.67, blue: 1.00)
        case .epic: return Color(red: 0.55, green: 0.35, blue: 1.00)
        case .legendary: return Color(red: 0.98, green: 0.80, blue: 0.27)
        }
    }
}

enum TrophyCategory: String, Codable, Hashable, CaseIterable {
    case distance, firsts, streak, social, seasonal, sponsor

    var title: String {
        switch self {
        case .distance: return "Distance"
        case .firsts: return "Firsts"
        case .streak: return "Streaks"
        case .social: return "Social"
        case .seasonal: return "Seasonal"
        case .sponsor: return "Sponsor drops"
        }
    }
}
