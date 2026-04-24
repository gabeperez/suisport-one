import Foundation
import Observation
import SwiftUI

/// Seeds realistic-looking social data so the UI has something to render
/// before the backend + indexer are live. Everything here is plausible shape,
/// not real state — swap each provider for an API call when ready.
@Observable
@MainActor
final class SocialDataService {
    static let shared = SocialDataService()

    // Core stores (mutable so kudos/comments/join state feels alive)
    var athletes: [Athlete] = []
    var feed: [FeedItem] = []
    var clubs: [Club] = []
    var challenges: [Challenge] = []
    var segments: [Segment] = []
    var trophies: [Trophy] = []
    var streak: Streak = Streak(currentDays: 0, longestDays: 0, weeklyStreakWeeks: 0,
                                atRiskByDate: nil, stakedSweat: 0, stakeExpiresAt: nil, multiplier: 1.0)
    var shoes: [Shoe] = []
    var personalRecords: [PersonalRecord] = []

    // Current user's athlete card (derived, kept in sync)
    var me: Athlete?

    private var seeded = false

    // MARK: - Seeding

    func seed(for user: User?, workouts: [Workout]) {
        guard !seeded else { return }
        seeded = true

        athletes = Self.seedAthletes()
        me = Self.buildSelf(from: user, workoutCount: workouts.count)
        feed = Self.seedFeed(me: me, others: athletes, userWorkouts: workouts)
        clubs = Self.seedClubs()
        challenges = Self.seedChallenges()
        segments = Self.seedSegments(others: athletes)
        trophies = Self.seedTrophies(workouts: workouts)
        streak = Self.seedStreak(workouts: workouts)
        shoes = Self.seedShoes()
        personalRecords = PRCalculator.all(from: workouts)

        // Auto-showcase the first three unlocked trophies so the profile
        // has something to flex by default.
        let autoShowcase = trophies.filter { !$0.isLocked }.prefix(3).map(\.id)
        if !autoShowcase.isEmpty, var me {
            me.showcasedTrophyIDs = Array(autoShowcase)
            self.me = me
        }
    }

    func reset() {
        seeded = false
        athletes = []
        feed = []
        clubs = []
        challenges = []
        segments = []
        trophies = []
        streak = Streak(currentDays: 0, longestDays: 0, weeklyStreakWeeks: 0,
                        atRiskByDate: nil, stakedSweat: 0, stakeExpiresAt: nil, multiplier: 1.0)
    }

    // MARK: - Live data refresh (Cloudflare API)
    //
    // Fetches feed + clubs + athletes + shoes + PRs in parallel. If any
    // call fails we keep the existing (seeded or stale) data — friends
    // testing should never see an empty screen because the network
    // hiccuped for a moment. Silent-on-error by design.

    var lastRefreshedAt: Date?
    var isRefreshing: Bool = false

    /// Cursor for the next page of feed items. `nil` after a refresh
    /// = more pages. `nil` after a loadMore that returned zero new
    /// items = end of feed. Private to this service; views trigger
    /// loadMoreFeed() and observe feed.count growing.
    private var feedNextBefore: Double?
    private var isLoadingMore = false
    var hasMoreFeed: Bool { feedNextBefore != nil }

    // Maps stable UUIDs (derived from backend IDs) back to the original
    // backend string IDs so mutations can address the server.
    private var feedItemApiIds: [UUID: String] = [:]
    private var clubApiIds: [UUID: String] = [:]
    private var shoeApiIds: [UUID: String] = [:]

    func apiIdForFeedItem(_ id: UUID) -> String { feedItemApiIds[id] ?? "" }
    func apiIdForClub(_ id: UUID) -> String { clubApiIds[id] ?? "" }
    func apiIdForShoe(_ id: UUID) -> String { shoeApiIds[id] ?? "" }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        async let feedResult: FeedEnvelope? = try? APIClient.shared.fetchFeedPage(sort: "recent", limit: 30)
        async let clubsResult: [ClubDTO]? = try? APIClient.shared.fetchClubs(filter: "all")
        async let meResult: AthleteDTO? = try? APIClient.shared.fetchMe()
        async let shoesResult: [ShoeDTO]? = try? APIClient.shared.fetchShoes(athleteId: "0xdemo_me")
        async let prsResult: [PRDTO]? = try? APIClient.shared.fetchPRs(athleteId: "0xdemo_me")

        let (fetchedFeed, fetchedClubs, fetchedMe, fetchedShoes, fetchedPRs) =
            await (feedResult, clubsResult, meResult, shoesResult, prsResult)

        if let env = fetchedFeed, !env.items.isEmpty {
            let items = env.items.map(FeedItem.init(dto:))
            feed = items
            feedItemApiIds = Dictionary(uniqueKeysWithValues:
                zip(items.map(\.id), env.items.map(\.id)))
            feedNextBefore = env.nextBefore
            // Harvest athletes from feed so profile taps resolve.
            let seen = Set(athletes.map(\.id))
            let newAthletes = env.items.map { Athlete(dto: $0.athlete) }
                .filter { !seen.contains($0.id) }
            athletes.append(contentsOf: newAthletes)
        }
        if let dtos = fetchedClubs, !dtos.isEmpty {
            let mapped = dtos.map(Club.init(dto:))
            clubs = mapped
            clubApiIds = Dictionary(uniqueKeysWithValues:
                zip(mapped.map(\.id), dtos.map(\.id)))
        }
        if let meDto = fetchedMe {
            me = Athlete(dto: meDto)
        }
        if let dtos = fetchedShoes {
            let mapped = dtos.map(Shoe.init(dto:))
            shoes = mapped
            shoeApiIds = Dictionary(uniqueKeysWithValues:
                zip(mapped.map(\.id), dtos.map(\.id)))
        }
        if let dtos = fetchedPRs, !dtos.isEmpty {
            personalRecords = dtos.map(PersonalRecord.init(dto:))
        }

        lastRefreshedAt = .now
    }

    /// Appends the next page of feed items if there's a cursor + we're
    /// not already fetching. No-op when we've reached the end.
    /// Silent-on-error: cursor keeps pointing at the same page so the
    /// next trigger retries.
    func loadMoreFeed() async {
        guard !isLoadingMore, let before = feedNextBefore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        guard let env = try? await APIClient.shared.fetchFeedPage(
            sort: "recent", limit: 30, before: before
        ), !env.items.isEmpty else {
            feedNextBefore = nil
            return
        }
        let newItems = env.items.map(FeedItem.init(dto:))
        let existingIds = Set(feed.map(\.id))
        let fresh = zip(newItems, env.items).filter { !existingIds.contains($0.0.id) }
        feed.append(contentsOf: fresh.map(\.0))
        for (m, dto) in fresh {
            feedItemApiIds[m.id] = dto.id
        }
        // Harvest athletes from the new page too.
        let seen = Set(athletes.map(\.id))
        let newAthletes = env.items.map { Athlete(dto: $0.athlete) }
            .filter { !seen.contains($0.id) }
        athletes.append(contentsOf: newAthletes)
        feedNextBefore = env.nextBefore
    }

    // MARK: - Actions (mutate local state, optimistic)

    func toggleKudos(on feedItemId: UUID, tip: Int = 0) {
        guard let idx = feed.firstIndex(where: { $0.id == feedItemId }),
              let me else { return }
        var item = feed[idx]
        let liking = !item.userHasKudosed
        if item.userHasKudosed {
            item.kudos.removeAll { $0.athlete.id == me.id }
            item.userHasKudosed = false
        } else {
            item.kudos.insert(Kudos(id: UUID(), athlete: me, amountSweat: tip, at: .now), at: 0)
            item.userHasKudosed = true
            item.tippedSweat += tip
        }
        feed[idx] = item
        // Fire to the server. We don't await — the UI already reflects the
        // optimistic mutation; the API call only matters so the next
        // refresh shows the right aggregate to other viewers.
        let apiId = apiIdForFeedItem(feedItemId)
        if !apiId.isEmpty {
            Task.detached {
                try? await APIClient.shared.toggleKudos(
                    feedItemId: apiId, tip: tip, liked: liking
                )
            }
        }
    }

    func addComment(_ body: String, to feedItemId: UUID) {
        guard let idx = feed.firstIndex(where: { $0.id == feedItemId }),
              let me else { return }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        feed[idx].comments.append(
            Comment(id: UUID(), athlete: me, body: trimmed, at: .now, reactions: [:])
        )
    }

    func toggleClubMembership(_ clubId: UUID) {
        guard let idx = clubs.firstIndex(where: { $0.id == clubId }) else { return }
        clubs[idx].isJoined.toggle()
        clubs[idx].memberCount += clubs[idx].isJoined ? 1 : -1
        let apiId = apiIdForClub(clubId)
        let joined = clubs[idx].isJoined
        if !apiId.isEmpty {
            Task.detached {
                if joined {
                    try? await APIClient.shared.joinClub(id: apiId)
                } else {
                    try? await APIClient.shared.leaveClub(id: apiId)
                }
            }
        }
    }

    func toggleChallengeJoin(_ challengeId: UUID) {
        guard let idx = challenges.firstIndex(where: { $0.id == challengeId }) else { return }
        challenges[idx].isJoined.toggle()
        challenges[idx].participants += challenges[idx].isJoined ? 1 : -1
        challenges[idx].prizePoolSweat += challenges[idx].isJoined ? challenges[idx].stakeSweat
                                                                  : -challenges[idx].stakeSweat
    }

    func toggleSegmentStar(_ segmentId: UUID) {
        guard let idx = segments.firstIndex(where: { $0.id == segmentId }) else { return }
        segments[idx].starred.toggle()
    }

    func stakeStreak(amount: Int) {
        streak.stakedSweat += amount
        streak.stakeExpiresAt = Calendar.current.date(byAdding: .day, value: 7, to: .now)
    }

    // MARK: - Profile editing

    func updateProfile(
        displayName: String? = nil,
        handle: String? = nil,
        bio: String? = nil,
        location: String? = nil,
        avatarTone: AvatarTone? = nil,
        bannerTone: AvatarTone? = nil,
        photoData: Data?? = nil,                     // double-optional: nil means "no change", .some(nil) means "clear"
        showcasedTrophyIDs: [UUID]? = nil
    ) {
        guard var current = me else { return }
        if let v = displayName?.trimmingCharacters(in: .whitespaces), !v.isEmpty {
            current.displayName = v
        }
        if let v = handle?.trimmingCharacters(in: .whitespaces), !v.isEmpty {
            current.handle = v
        }
        if let v = bio {
            current.bio = v.trimmingCharacters(in: .whitespaces).isEmpty ? nil : v
        }
        if let v = location {
            current.location = v.trimmingCharacters(in: .whitespaces).isEmpty ? nil : v
        }
        if let tone = avatarTone { current.avatarTone = tone }
        if let tone = bannerTone { current.bannerTone = tone }
        if let photo = photoData {
            current.photoData = photo          // photo may be nil to clear
        }
        if let ids = showcasedTrophyIDs {
            current.showcasedTrophyIDs = Array(ids.prefix(3))
        }
        self.me = current

        // Fire-and-forget sync to the server. Server's Zod schema
        // rejects handles that don't match [a-z0-9_]{2,24} — EditProfile
        // UI enforces the same constraint up-front, but if a bad value
        // sneaks through, the local optimistic change stays and the
        // next refresh() pulls whatever the server chose to accept.
        let patch = AthletePatch(
            displayName: displayName?.trimmingCharacters(in: .whitespaces),
            handle: handle?.trimmingCharacters(in: .whitespaces),
            bio: bio,
            location: location,
            avatarTone: avatarTone?.rawValue,
            bannerTone: bannerTone?.rawValue,
            photoR2Key: nil
        )
        Task.detached {
            _ = try? await APIClient.shared.updateMe(patch)
        }
    }

    func retireShoe(_ id: UUID) {
        guard let i = shoes.firstIndex(where: { $0.id == id }) else { return }
        shoes[i].retired.toggle()
    }

    func addShoe(brand: String, model: String, nickname: String?,
                 tone: AvatarTone, milesTotal: Double) {
        let localId = UUID()
        let shoe = Shoe(
            id: localId,
            brand: brand.trimmingCharacters(in: .whitespaces),
            model: model.trimmingCharacters(in: .whitespaces),
            nickname: nickname?.trimmingCharacters(in: .whitespaces).isEmpty == true ? nil : nickname,
            tone: tone,
            milesUsed: 0,
            milesTotal: milesTotal,
            retired: false,
            startedAt: .now
        )
        shoes.insert(shoe, at: 0)
        // Persist to the server so the shoe shows up on other devices.
        let req = AddShoeRequest(
            brand: shoe.brand, model: shoe.model,
            nickname: shoe.nickname, tone: tone.rawValue,
            milesTotal: milesTotal
        )
        // Task (not .detached) inherits MainActor isolation from the
        // caller, so `self` capture is safe and we don't need a nested
        // MainActor.run hop.
        Task { [weak self] in
            guard let self else { return }
            if let serverId = try? await APIClient.shared.addShoe(req) {
                self.shoeApiIds[localId] = serverId
            }
        }
    }

    func createClub(name: String, handle: String, tagline: String,
                    description: String, tone: AvatarTone) {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedHandle = handle.trimmingCharacters(in: .whitespaces)
        let localId = UUID()
        let club = Club(
            id: localId,
            name: trimmedName,
            handle: trimmedHandle,
            tagline: tagline.trimmingCharacters(in: .whitespaces),
            description: description.trimmingCharacters(in: .whitespaces),
            heroTone: tone,
            memberCount: 1,
            sweatTreasury: 0,
            isJoined: true,
            isVerifiedBrand: false,
            weeklyKm: 0,
            tags: [],
            activeChallengeIDs: []
        )
        clubs.insert(club, at: 0)
        let req = CreateClubRequest(
            name: trimmedName, handle: trimmedHandle,
            tagline: club.tagline, description: club.description,
            heroTone: tone.rawValue, tags: []
        )
        Task { [weak self] in
            guard let self else { return }
            if let serverId = try? await APIClient.shared.createClub(req) {
                self.clubApiIds[localId] = serverId
            }
        }
    }

    func muteAthlete(_ athleteId: String) {
        feed.removeAll { $0.athlete.id == athleteId }
    }

    func reportFeedItem(_ itemId: UUID, reason: String) {
        // Local-only: hide the item and tag the reason. Once the indexer is
        // live this will POST to the moderation endpoint.
        feed.removeAll { $0.id == itemId }
    }

    // MARK: - Aggregates

    func lifetime(from workouts: [Workout]) -> LifetimeTotals {
        var t = LifetimeTotals()
        for w in workouts {
            t.seconds += w.duration
            t.kcal += w.energyKcal ?? 0
            let d = w.distanceMeters ?? 0
            switch w.type {
            case .run: t.runMeters += d
            case .walk: t.walkMeters += d
            case .ride: t.rideMeters += d
            case .hike: t.hikeMeters += d
            case .swim: t.swimMeters += d
            default: break
            }
            t.workouts += 1
        }
        return t
    }
}

struct LifetimeTotals {
    var workouts: Int = 0
    var runMeters: Double = 0
    var walkMeters: Double = 0
    var rideMeters: Double = 0
    var hikeMeters: Double = 0
    var swimMeters: Double = 0
    var seconds: TimeInterval = 0
    var kcal: Double = 0

    var totalDistanceMeters: Double { runMeters + walkMeters + rideMeters + hikeMeters + swimMeters }
}

// MARK: - Seed data

private extension SocialDataService {

    static func buildSelf(from user: User?, workoutCount: Int) -> Athlete {
        let handle = user?.displayName.lowercased().replacingOccurrences(of: " ", with: "_") ?? "you"
        return Athlete(
            id: user?.id ?? "local_me",          // UUID if signed in, stable placeholder otherwise
            suiAddress: user?.suiAddress,
            handle: handle,
            displayName: user?.displayName ?? "You",
            avatarTone: AvatarTone.tone(for: handle),
            verified: false,
            tier: Self.tierFor(workouts: workoutCount),
            totalWorkouts: workoutCount,
            followers: 0,
            following: 12,
            bio: "Running, riding, and earning Sweat.",
            suinsName: user?.suinsName
        )
    }

    static func tierFor(workouts: Int) -> AthleteTier {
        switch workouts {
        case ..<AthleteTier.bronze.threshold: return .starter
        case ..<AthleteTier.silver.threshold: return .bronze
        case ..<AthleteTier.gold.threshold: return .silver
        case ..<AthleteTier.legend.threshold: return .gold
        default: return .legend
        }
    }

    static func seedAthletes() -> [Athlete] {
        [
            Athlete.preview("ajoy", name: "Ajoy Ramirez", tier: .gold),
            Athlete.preview("harper", name: "Harper Lin", tier: .silver),
            Athlete.preview("kip_e", name: "Eliud K.", tier: .legend, verified: true),
            Athlete.preview("sam", name: "Sam Patel", tier: .silver),
            Athlete.preview("nico", name: "Nico Ferrer", tier: .bronze),
            Athlete.preview("teddy", name: "Teddy Cho", tier: .silver),
            Athlete.preview("ris", name: "Iris Novak", tier: .gold),
            Athlete.preview("maya", name: "Maya Ford", tier: .bronze),
            Athlete.preview("jun", name: "Jun Takahashi", tier: .legend, verified: true),
            Athlete.preview("leo", name: "Leo Marchetti", tier: .starter),
            Athlete.preview("zoe", name: "Zoe Watkins", tier: .silver),
            Athlete.preview("dre", name: "Andre Johnson", tier: .gold)
        ]
    }

    static func seedFeed(me: Athlete?, others: [Athlete], userWorkouts: [Workout]) -> [FeedItem] {
        var items: [FeedItem] = []

        // First: the user's own recent workouts, wrapped as feed items.
        if let me {
            for w in userWorkouts.prefix(12) {
                items.append(FeedItem(
                    id: UUID(),
                    athlete: me,
                    workout: w,
                    title: defaultTitle(for: w, hour: Calendar.current.component(.hour, from: w.startDate)),
                    caption: w.points > 120 ? "Felt strong today." : nil,
                    mapPreviewSeed: Int.random(in: 0...999),
                    kudos: [],
                    comments: [],
                    userHasKudosed: false,
                    tippedSweat: 0,
                    taggedAthleteIDs: []
                ))
            }
        }

        // Others' workouts — fully fabricated but realistic.
        let captions = [
            "Clean miles. Negative split 🔥",
            "Easy Zone 2. No complaints.",
            "Hills. My legs hate me.",
            "Coach Bennett told me to chill, and I obeyed.",
            "Rainy one. Didn't miss a beat.",
            "Group run! Pace was spicy.",
            "PR on the canal segment. Long live QOM.",
            nil,
            "Recovery ride. Coffee first, always.",
            "Weekend long run. Peak week of block 2."
        ]

        var cursor = Date()
        for (i, athlete) in others.enumerated() {
            let dec = Double.random(in: 3*3600...48*3600)
            cursor = cursor.addingTimeInterval(-dec)
            let type: WorkoutType = [.run, .run, .ride, .run, .walk, .lift, .yoga, .run, .hike, .hiit][i % 10]
            let duration = Double.random(in: 1200...5400)
            let dist: Double? = (type == .run || type == .ride || type == .walk || type == .hike)
                ? Double.random(in: 2000...18000)
                : nil

            let w = Workout(
                id: UUID(),
                type: type,
                startDate: cursor.addingTimeInterval(-duration),
                endDate: cursor,
                duration: duration,
                distanceMeters: dist,
                energyKcal: Double.random(in: 180...900),
                avgHeartRate: Double.random(in: 120...165),
                source: "com.suisport.app",
                isUserEntered: false,
                points: 0,
                verified: true,
                synced: true
            )
            var wWithPoints = w
            wWithPoints.points = SweatPoints.forWorkout(w)

            // Random subset of other athletes leave kudos
            let kudosersCount = Int.random(in: 0...6)
            let kudosers = others.filter { $0.id != athlete.id }
                                 .shuffled().prefix(kudosersCount)
            let kudos: [Kudos] = kudosers.map { a in
                let tip = Int.random(in: 0...4) == 0 ? Int.random(in: 1...8) : 0
                return Kudos(id: UUID(), athlete: a, amountSweat: tip,
                             at: cursor.addingTimeInterval(Double.random(in: 100...4000)))
            }
            let tippedSweat = kudos.reduce(0) { $0 + $1.amountSweat }

            // 0-3 comments
            let cmts: [Comment] = (0..<Int.random(in: 0...3)).compactMap { _ in
                guard let who = others.randomElement(), who.id != athlete.id else { return nil }
                return Comment(
                    id: UUID(),
                    athlete: who,
                    body: ["Sick pace 🔥", "Send it", "Big if true",
                           "Catch up to me lol", "Absolute unit", "Easy day 💀",
                           "Tip incoming", "You animal"].randomElement() ?? "Nice",
                    at: cursor.addingTimeInterval(Double.random(in: 500...12000)),
                    reactions: ["👏": Int.random(in: 0...4), "🔥": Int.random(in: 0...3)]
                        .filter { $0.value > 0 }
                )
            }

            items.append(FeedItem(
                id: UUID(),
                athlete: athlete,
                workout: wWithPoints,
                title: defaultTitle(for: wWithPoints,
                                    hour: Calendar.current.component(.hour, from: wWithPoints.startDate)),
                caption: captions.randomElement() ?? nil,
                mapPreviewSeed: Int.random(in: 0...999),
                kudos: kudos,
                comments: cmts,
                userHasKudosed: false,
                tippedSweat: tippedSweat,
                taggedAthleteIDs: []
            ))
        }

        return items.sorted { $0.workout.startDate > $1.workout.startDate }
    }

    static func defaultTitle(for w: Workout, hour: Int) -> String {
        let timeOfDay: String
        switch hour {
        case 5..<10: timeOfDay = "Morning"
        case 10..<14: timeOfDay = "Midday"
        case 14..<18: timeOfDay = "Afternoon"
        case 18..<22: timeOfDay = "Evening"
        default: timeOfDay = "Late-night"
        }
        return "\(timeOfDay) \(w.type.title.lowercased())"
    }

    static func seedClubs() -> [Club] {
        [
            Club(id: UUID(), name: "Brooklyn Dawn Patrol", handle: "dawn_patrol",
                 tagline: "6AM on the bridge. No excuses.",
                 description: "Dawn runs, cold coffee, warm hearts. Meet at the Brooklyn Bridge plaza, 6am sharp.",
                 heroTone: .sunset, memberCount: 1248, sweatTreasury: 14_200,
                 isJoined: true, isVerifiedBrand: false, weeklyKm: 842,
                 tags: ["running", "NYC"], activeChallengeIDs: []),
            Club(id: UUID(), name: "Rapha Cycling Club", handle: "rcc",
                 tagline: "Ride for the story.",
                 description: "Global members-only cycling club. Sponsored rides, shop access, regional hubs.",
                 heroTone: .ocean, memberCount: 148_512, sweatTreasury: 820_000,
                 isJoined: false, isVerifiedBrand: true, weeklyKm: 98_224,
                 tags: ["cycling", "brand"], activeChallengeIDs: []),
            Club(id: UUID(), name: "SuiSport Founders' Circle", handle: "sui_core",
                 tagline: "The earliest athletes on chain.",
                 description: "Our OGs. Soulbound membership, founder-drop gear, monthly AMA with the team.",
                 heroTone: .grape, memberCount: 412, sweatTreasury: 55_000,
                 isJoined: true, isVerifiedBrand: true, weeklyKm: 4_120,
                 tags: ["community"], activeChallengeIDs: []),
            Club(id: UUID(), name: "Marathon Maniacs", handle: "26point2",
                 tagline: "Because one is never enough.",
                 description: "Multi-marathoners unite. Prove your finishes, stake on race PRs.",
                 heroTone: .ember, memberCount: 8_442, sweatTreasury: 120_500,
                 isJoined: false, isVerifiedBrand: false, weeklyKm: 21_440,
                 tags: ["running", "marathon"], activeChallengeIDs: []),
            Club(id: UUID(), name: "Trail Freaks", handle: "trailfreaks",
                 tagline: "Dirt, elevation, mud. Repeat.",
                 description: "Weekend trail crew. Share routes, beta, ride share. Verified elevation only.",
                 heroTone: .forest, memberCount: 3_128, sweatTreasury: 18_200,
                 isJoined: false, isVerifiedBrand: false, weeklyKm: 6_880,
                 tags: ["trail", "ultra"], activeChallengeIDs: []),
            Club(id: UUID(), name: "Lift & Chill", handle: "lift_chill",
                 tagline: "Heavy lifts, heavier naps.",
                 description: "Strength-first club. Program swaps, PR celebrations, weekly check-ins.",
                 heroTone: .slate, memberCount: 2_240, sweatTreasury: 12_400,
                 isJoined: false, isVerifiedBrand: false, weeklyKm: 0,
                 tags: ["strength"], activeChallengeIDs: [])
        ]
    }

    static func seedChallenges() -> [Challenge] {
        let now = Date()
        let cal = Calendar.current
        func plus(_ d: Int) -> Date { cal.date(byAdding: .day, value: d, to: now) ?? now }
        func minus(_ d: Int) -> Date { cal.date(byAdding: .day, value: -d, to: now) ?? now }

        return [
            Challenge(
                id: UUID(), title: "April 100k",
                subtitle: "Run 100 km this month",
                kind: .distance,
                sponsor: nil,
                goal: ChallengeGoal(kind: .distance, target: 100, unit: "km"),
                currentProgress: 0.42,
                startsAt: minus(23), endsAt: plus(7),
                stakeSweat: 0, prizePoolSweat: 0, participants: 28_411,
                isJoined: true, hero: .ember, badgeIcon: "medal.star.fill"
            ),
            Challenge(
                id: UUID(), title: "Sub-3 May",
                subtitle: "Nike x SuiSport marathon prep block",
                kind: .workouts,
                sponsor: Sponsor(name: "Nike", handle: "nike", color: "#111111"),
                goal: ChallengeGoal(kind: .workouts, target: 24, unit: "workouts"),
                currentProgress: 0.0,
                startsAt: plus(7), endsAt: plus(38),
                stakeSweat: 50, prizePoolSweat: 125_000, participants: 1_402,
                isJoined: false, hero: .grape, badgeIcon: "figure.run.square.stack.fill"
            ),
            Challenge(
                id: UUID(), title: "Streak Week",
                subtitle: "Log a workout every day this week",
                kind: .streak,
                sponsor: nil,
                goal: ChallengeGoal(kind: .streak, target: 7, unit: "days"),
                currentProgress: 0.71,
                startsAt: minus(5), endsAt: plus(2),
                stakeSweat: 25, prizePoolSweat: 18_240, participants: 3_221,
                isJoined: true, hero: .sunset, badgeIcon: "flame.fill"
            ),
            Challenge(
                id: UUID(), title: "Everest in April",
                subtitle: "Climb 8,848 m total",
                kind: .elevation,
                sponsor: nil,
                goal: ChallengeGoal(kind: .elevation, target: 8848, unit: "m"),
                currentProgress: 0.08,
                startsAt: minus(23), endsAt: plus(7),
                stakeSweat: 0, prizePoolSweat: 0, participants: 5_120,
                isJoined: false, hero: .forest, badgeIcon: "mountain.2.fill"
            ),
            Challenge(
                id: UUID(), title: "Canal Loop TT",
                subtitle: "Beat your best time on the 5k canal segment",
                kind: .segment,
                sponsor: Sponsor(name: "On", handle: "on_running", color: "#FF5300"),
                goal: ChallengeGoal(kind: .segment, target: 1, unit: "attempt"),
                currentProgress: 0.0,
                startsAt: minus(1), endsAt: plus(14),
                stakeSweat: 10, prizePoolSweat: 4_200, participants: 288,
                isJoined: false, hero: .ocean, badgeIcon: "stopwatch.fill"
            )
        ]
    }

    static func seedSegments(others: [Athlete]) -> [Segment] {
        func entry(_ a: Athlete, _ secs: Int) -> LeaderboardEntry {
            LeaderboardEntry(id: UUID(), athlete: a, timeSeconds: secs, attempts: Int.random(in: 1...22),
                             achievedAt: Date().addingTimeInterval(-Double.random(in: 1_000...3_000_000)))
        }
        func legend(_ a: Athlete) -> LeaderboardEntry {
            LeaderboardEntry(id: UUID(), athlete: a, timeSeconds: 0, attempts: Int.random(in: 40...120),
                             achievedAt: Date().addingTimeInterval(-Double.random(in: 100_000...8_000_000)))
        }
        return [
            Segment(id: UUID(), name: "Prospect Park Outer Loop",
                    location: "Brooklyn, NY",
                    distanceMeters: 5320, elevationGainM: 58, avgGradePct: 1.2,
                    totalAttempts: 184_402, athleteCount: 21_811,
                    kom: entry(others[2], 872), qom: entry(others[6], 942),
                    localLegend: legend(others[0]),
                    myBest: entry(others[3], 1160), myRank: 2_221,
                    starred: true, surface: .road, heroTone: .forest),
            Segment(id: UUID(), name: "Manhattan Bridge Climb",
                    location: "New York, NY",
                    distanceMeters: 720, elevationGainM: 33, avgGradePct: 4.6,
                    totalAttempts: 92_208, athleteCount: 18_442,
                    kom: entry(others[8], 126), qom: entry(others[10], 141),
                    localLegend: legend(others[4]),
                    myBest: entry(others[3], 172), myRank: 812,
                    starred: false, surface: .road, heroTone: .slate),
            Segment(id: UUID(), name: "Rockaway Flats TT",
                    location: "Queens, NY",
                    distanceMeters: 10_000, elevationGainM: 0, avgGradePct: 0,
                    totalAttempts: 12_420, athleteCount: 3_228,
                    kom: entry(others[8], 1482), qom: entry(others[11], 1604),
                    localLegend: legend(others[1]),
                    myBest: nil, myRank: nil,
                    starred: false, surface: .road, heroTone: .ocean),
            Segment(id: UUID(), name: "Bear Mountain Main",
                    location: "Hudson Valley, NY",
                    distanceMeters: 2400, elevationGainM: 210, avgGradePct: 8.8,
                    totalAttempts: 8_110, athleteCount: 2_088,
                    kom: entry(others[0], 518), qom: entry(others[6], 572),
                    localLegend: legend(others[7]),
                    myBest: nil, myRank: nil,
                    starred: true, surface: .trail, heroTone: .ember)
        ]
    }

    static func seedTrophies(workouts: [Workout]) -> [Trophy] {
        let totalKm = workouts.reduce(0.0) { $0 + ($1.distanceMeters ?? 0) / 1000 }
        let totalWorkouts = workouts.count

        func trophy(_ title: String, _ sub: String, icon: String, rarity: Rarity,
                    progress: Double, cat: TrophyCategory, colors: [String],
                    earned: Bool = false, daysAgo: Int = 7) -> Trophy {
            Trophy(
                id: UUID(), title: title, subtitle: sub, icon: icon, rarity: rarity,
                earnedAt: earned ? Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) : nil,
                progress: progress, category: cat,
                gradient: colors.map(hexColor)
            )
        }
        return [
            trophy("First Workout", "Logged your first session", icon: "sparkles",
                   rarity: .common, progress: min(1, Double(totalWorkouts)),
                   cat: .firsts, colors: ["#A3FF70", "#0F6B38"],
                   earned: totalWorkouts >= 1, daysAgo: 30),
            trophy("5K Finisher", "Run 5 km in one workout", icon: "figure.run.circle.fill",
                   rarity: .common,
                   progress: min(1, (workouts.first(where: { ($0.distanceMeters ?? 0) >= 5000 }) != nil) ? 1 : 0),
                   cat: .firsts, colors: ["#FFB020", "#FF5C2A"],
                   earned: workouts.contains { ($0.distanceMeters ?? 0) >= 5000 }, daysAgo: 10),
            trophy("10K Club", "Run 10 km in one workout", icon: "10.circle.fill",
                   rarity: .rare,
                   progress: min(1, (workouts.compactMap { $0.distanceMeters }.max() ?? 0) / 10000),
                   cat: .firsts, colors: ["#45A9FF", "#275EC7"]),
            trophy("Half Marathon", "Run 21.1 km in one workout", icon: "figure.run.motion",
                   rarity: .epic,
                   progress: min(1, (workouts.compactMap { $0.distanceMeters }.max() ?? 0) / 21100),
                   cat: .firsts, colors: ["#B57BFF", "#5534BF"]),
            trophy("First Marathon", "Finish a 42.2 km run", icon: "trophy.fill",
                   rarity: .legendary,
                   progress: min(1, (workouts.compactMap { $0.distanceMeters }.max() ?? 0) / 42195),
                   cat: .firsts, colors: ["#FFD246", "#E26C00"]),
            trophy("100k Total", "Run 100 km across all workouts", icon: "chart.bar.fill",
                   rarity: .rare, progress: min(1, totalKm / 100),
                   cat: .distance, colors: ["#8CF0A3", "#1B7A3F"],
                   earned: totalKm >= 100, daysAgo: 3),
            trophy("7-Day Streak", "Work out 7 days in a row", icon: "flame.fill",
                   rarity: .rare, progress: 0.43, cat: .streak,
                   colors: ["#FF8A5C", "#C7321E"]),
            trophy("30-Day Streak", "Work out 30 days in a row", icon: "flame.fill",
                   rarity: .epic, progress: 0.12, cat: .streak,
                   colors: ["#FF3B8A", "#8B1044"]),
            trophy("Kudos Giver", "Send 100 kudos to friends", icon: "hand.thumbsup.fill",
                   rarity: .common, progress: 0.22, cat: .social,
                   colors: ["#9EE7FF", "#2B6EA3"]),
            trophy("Patron", "Tip 500 Sweat to other athletes", icon: "heart.circle.fill",
                   rarity: .epic, progress: 0.05, cat: .social,
                   colors: ["#FFB3D2", "#94325E"]),
            trophy("April 100k Finisher", "Hit 100 km in April", icon: "medal.star.fill",
                   rarity: .rare, progress: 0.42, cat: .seasonal,
                   colors: ["#F8D35B", "#AE6E1C"]),
            trophy("Nike Founders' Drop", "Early access to limited-edition Vaporfly",
                   icon: "bag.fill.badge.plus",
                   rarity: .legendary, progress: 0.0, cat: .sponsor,
                   colors: ["#1A1A1A", "#5A5A5A"])
        ]
    }

    static func seedShoes() -> [Shoe] {
        let now = Date()
        func started(daysAgo: Int) -> Date {
            Calendar.current.date(byAdding: .day, value: -daysAgo, to: now) ?? now
        }
        return [
            Shoe(id: UUID(), brand: "Nike", model: "Vaporfly 3", nickname: "Race day",
                 tone: .ember, milesUsed: 142, milesTotal: 400,
                 retired: false, startedAt: started(daysAgo: 160)),
            Shoe(id: UUID(), brand: "Hoka", model: "Clifton 9", nickname: "Daily driver",
                 tone: .ocean, milesUsed: 468, milesTotal: 500,
                 retired: false, startedAt: started(daysAgo: 210)),
            Shoe(id: UUID(), brand: "Saucony", model: "Endorphin Speed 4", nickname: "Workout day",
                 tone: .grape, milesUsed: 88, milesTotal: 450,
                 retired: false, startedAt: started(daysAgo: 60)),
            Shoe(id: UUID(), brand: "On", model: "Cloudmonster 2", nickname: "Easy miles",
                 tone: .mint, milesUsed: 310, milesTotal: 450,
                 retired: false, startedAt: started(daysAgo: 240))
        ]
    }

    static func seedStreak(workouts: [Workout]) -> Streak {
        let days = Set(workouts.map { Calendar.current.startOfDay(for: $0.startDate) })
        var streak = 0
        var cursor = Calendar.current.startOfDay(for: .now)
        while days.contains(cursor) {
            streak += 1
            guard let prev = Calendar.current.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }

        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))

        return Streak(
            currentDays: streak,
            longestDays: max(streak, 14),
            weeklyStreakWeeks: max(4, streak / 7),
            atRiskByDate: tomorrow,
            stakedSweat: 0,
            stakeExpiresAt: nil,
            multiplier: 1.0 + min(2.0, Double(streak) * 0.05)
        )
    }

    static func hexColor(_ hex: String) -> Color {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xff) / 255
        let g = Double((value >> 8) & 0xff) / 255
        let b = Double(value & 0xff) / 255
        return Color(red: r, green: g, blue: b)
    }
}
