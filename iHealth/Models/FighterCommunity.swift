import Foundation

/// A fighter's gated community space — the SuiSport take on Weverse /
/// Fansly. Fans unlock by either burning Sweat (instant) or completing
/// the fighter's training program (sweat-equity). Once unlocked, users
/// see the full feed of fighter-authored posts: training tips, fight
/// prep, AMAs, behind-the-scenes video.
///
/// Phase 1 ships locked-preview + Sweat-spend unlock; training-based
/// unlock is stubbed for visual purposes (the requirement copy shows
/// up in the locked state but completion isn't tracked yet).
struct FighterCommunity: Identifiable, Hashable, Codable {
    /// Same as `Athlete.id` — one community per fighter.
    var id: String
    var unlockSweatCost: Int
    /// Free preview hint for the locked state — number of training
    /// sessions of the fighter's discipline the user would need to
    /// auto-unlock (Phase 3).
    var requiredWorkoutType: String
    var requiredWorkoutCount: Int
    var description: String
    var posts: [CommunityPost]
}

/// A single post in a fighter's community feed.
struct CommunityPost: Identifiable, Hashable, Codable {
    var id: UUID
    var kind: Kind
    var title: String
    var body: String
    var createdAt: Date
    /// YouTube watch URL (e.g. `https://www.youtube.com/watch?v=jLOcGuT-JAI`).
    /// The post card extracts the video id and embeds via WKWebView.
    var youtubeURL: String?
    /// One post per community is flagged as the free preview — visible
    /// even when locked so casual fans see what they're missing.
    var isFreePreview: Bool

    enum Kind: String, Codable, Hashable, CaseIterable {
        case message     // text + optional video
        case trainingTip // text-only training advice
        case ama         // Q&A snippet
        case announcement
        case fightWeek

        var label: String {
            switch self {
            case .message:      return "Message"
            case .trainingTip:  return "Training tip"
            case .ama:          return "AMA"
            case .announcement: return "Announcement"
            case .fightWeek:    return "Fight week"
            }
        }

        var icon: String {
            switch self {
            case .message:      return "bubble.left.and.bubble.right.fill"
            case .trainingTip:  return "figure.strengthtraining.traditional"
            case .ama:          return "questionmark.bubble.fill"
            case .announcement: return "megaphone.fill"
            case .fightWeek:    return "flame.fill"
            }
        }
    }
}

extension FighterCommunity {
    /// Tier-based unlock cost, tuned so legends feel premium and
    /// starters are accessible. All seeded ONE Championship fighters
    /// are legends in this build, so the demo path uses the 250
    /// number.
    static func unlockCost(for tier: AthleteTier) -> Int {
        switch tier {
        case .legend:  return 250
        case .gold:    return 150
        case .silver:  return 100
        case .bronze:  return 75
        case .starter: return 50
        }
    }
}
