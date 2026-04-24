import Foundation
import CryptoKit
import SwiftUI

// Bridge layer between the Cloudflare API's string-keyed DTOs and the
// app's existing UUID-keyed domain models. Backend IDs ("fi_demo_1",
// "0xdemo_ajoy", etc.) are not valid UUIDs, so we hash them into a
// deterministic UUID — same input always yields the same UUID, which
// keeps SwiftUI list diffing stable across refreshes.
//
// Scope for the beta: Athlete, Workout, FeedItem, Club, Shoe, PR.
// Segment and Trophy keep using local seeds for now — their on-chain
// shape is still in flux and the visual richness lives in iOS fields
// the backend doesn't ship yet.

extension UUID {
    static func stable(from s: String) -> UUID {
        let hash = SHA256.hash(data: Data(s.utf8))
        var bytes = [UInt8](hash.prefix(16))
        // Shape the bytes like a UUID v5 (name-based SHA-1, RFC 4122 variant).
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

// MARK: - Athlete

extension Athlete {
    init(dto: AthleteDTO) {
        self.init(
            id: dto.id,
            handle: dto.handle,
            displayName: dto.displayName,
            avatarTone: AvatarTone(rawValue: dto.avatarTone) ?? .sunset,
            verified: dto.verified,
            tier: AthleteTier(rawValue: dto.tier) ?? .starter,
            totalWorkouts: dto.totalWorkouts,
            followers: dto.followers,
            following: dto.following,
            bio: dto.bio,
            bannerTone: AvatarTone(rawValue: dto.bannerTone) ?? .sunset,
            photoData: nil,
            showcasedTrophyIDs: [],
            location: dto.location,
            suinsName: dto.suinsName
        )
    }
}

// MARK: - Workout

extension Workout {
    init(dto: WorkoutDTO) {
        let start = Date(timeIntervalSince1970: dto.startDate)
        let typeVal = WorkoutType(rawValue: dto.type) ?? .other
        self.init(
            id: UUID.stable(from: dto.id),
            type: typeVal,
            startDate: start,
            endDate: start.addingTimeInterval(dto.durationSeconds),
            duration: dto.durationSeconds,
            distanceMeters: dto.distanceMeters,
            energyKcal: dto.energyKcal,
            avgHeartRate: dto.avgHeartRate,
            source: "cloud.suisport",
            isUserEntered: false,
            points: dto.points,
            verified: dto.verified,
            synced: true
        )
    }
}

// MARK: - FeedItem

extension FeedItem {
    init(dto: FeedItemDTO) {
        // The server returns aggregate counts, not individual kudos/comment
        // rows. Synthesize placeholder arrays sized to the counts so the UI's
        // `kudos.count` / `comments.count` still work. Callers that need
        // per-row data hit `/v1/feed/:id/comments`.
        let placeholderKudos = Array(repeating: Kudos(
            id: UUID(), athlete: Athlete(dto: dto.athlete),
            amountSweat: 0, at: .now
        ), count: dto.kudosCount)
        let placeholderComments = Array(repeating: Comment(
            id: UUID(), athlete: Athlete(dto: dto.athlete),
            body: "", at: .now, reactions: [:]
        ), count: dto.commentCount)
        self.init(
            id: UUID.stable(from: dto.id),
            athlete: Athlete(dto: dto.athlete),
            workout: Workout(dto: dto.workout),
            title: dto.title,
            caption: dto.caption,
            mapPreviewSeed: dto.mapPreviewSeed,
            kudos: placeholderKudos,
            comments: placeholderComments,
            userHasKudosed: false,
            tippedSweat: dto.tippedSweat,
            taggedAthleteIDs: []
        )
    }
}

// MARK: - Club

extension Club {
    init(dto: ClubDTO) {
        self.init(
            id: UUID.stable(from: dto.id),
            name: dto.name,
            handle: dto.handle,
            tagline: dto.tagline ?? "",
            description: dto.description ?? "",
            heroTone: AvatarTone(rawValue: dto.heroTone) ?? .sunset,
            memberCount: dto.memberCount,
            sweatTreasury: dto.sweatTreasury,
            isJoined: false,
            isVerifiedBrand: dto.isVerifiedBrand,
            weeklyKm: dto.weeklyKm,
            tags: dto.tags,
            activeChallengeIDs: []
        )
    }
}

// MARK: - Shoe

extension Shoe {
    init(dto: ShoeDTO) {
        self.init(
            id: UUID.stable(from: dto.id),
            brand: dto.brand,
            model: dto.model,
            nickname: dto.nickname,
            tone: AvatarTone(rawValue: dto.tone) ?? .sunset,
            milesUsed: dto.milesUsed,
            milesTotal: dto.milesTotal,
            retired: dto.retired,
            startedAt: Date(timeIntervalSince1970: dto.startedAt)
        )
    }
}

// MARK: - Personal record

extension PersonalRecord {
    init(dto: PRDTO) {
        self.init(
            label: dto.label,
            distanceMeters: dto.distanceMeters,
            bestTimeSeconds: dto.bestTimeSeconds,
            achievedAt: dto.achievedAt.map { Date(timeIntervalSince1970: $0) }
        )
    }
}
