import Foundation
import SwiftUI

/// Achievement / trophy. Soulbound in the Move package — portable across
/// fitness apps, flex-able on any chain viewer.
struct Trophy: Identifiable, Hashable {
    var id: UUID
    var title: String
    var subtitle: String
    var icon: String                 // SF Symbol
    var rarity: Rarity
    var earnedAt: Date?              // nil if locked
    var progress: Double             // 0...1 toward unlocking
    var category: TrophyCategory
    var gradient: [Color]            // cosmetic — a two-stop gradient

    var isLocked: Bool { earnedAt == nil }
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
