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
    /// Per-fighter community config + posts. Lookup via athleteId.
    /// Seeded statically — Phase 2 moves to a server-driven feed.
    var communities: [String: FighterCommunity] = [:]
    /// Per-fighter training camps. Same lookup pattern as communities.
    var trainingPlans: [String: FighterTrainingPlan] = [:]

    // Current user's athlete card (derived, kept in sync)
    var me: Athlete?

    private var seeded = false

    // MARK: - Seeding

    func seed(for user: User?, workouts: [Workout]) {
        guard !seeded else { return }
        seeded = true

        // Hydrate athletes from disk first so feed-card avatar taps
        // resolve before refresh() lands. Falls back to fixtures only
        // if there's nothing cached (first launch / signed-out user).
        let cachedAthletes = AppPersistence.loadAthletes()
        athletes = cachedAthletes.isEmpty ? Self.seedAthletes() : cachedAthletes

        // Prefer the persisted social profile over a rebuild-from-User
        // stub so the user's customized handle, photo, tones, and
        // showcase show up instantly on relaunch — even if /me is
        // slow or unreachable.
        if let cached = AppPersistence.loadMe() {
            me = cached
        } else {
            me = Self.buildSelf(from: user, workoutCount: workouts.count)
        }

        // Hydrate the feed from disk too so the user lands on real
        // content instead of a blank list while refresh() runs.
        let cachedFeed = AppPersistence.loadFeed()
        if !cachedFeed.isEmpty {
            feed = cachedFeed
        } else {
            feed = Self.seedFeed(me: me, others: athletes, userWorkouts: workouts)
        }
        clubs = Self.seedClubs()
        challenges = Self.seedChallenges()
        segments = Self.seedSegments(others: athletes)
        trophies = Self.seedTrophies(workouts: workouts)
        streak = Self.seedStreak(workouts: workouts)
        shoes = Self.seedShoes()
        personalRecords = PRCalculator.all(from: workouts)
        communities = Self.seedCommunities(athletes: athletes)
        trainingPlans = Self.seedTrainingPlans(athletes: athletes)

        // Auto-showcase the first three unlocked trophies so a fresh
        // profile has something to flex by default. Skip when the
        // cached `me` already has a user-picked showcase — otherwise
        // we'd stomp the user's selections every relaunch.
        // Defensive prune of stale showcase entries (e.g. UUID strings
        // persisted before the [UUID] → [String stableKey] migration,
        // or trophies that have since been removed from the catalog).
        if var meCopy = me {
            let validKeys = Set(trophies.map(\.stableKey))
            let cleaned = meCopy.showcasedTrophyIDs.filter { validKeys.contains($0) }
            if cleaned.count != meCopy.showcasedTrophyIDs.count {
                meCopy.showcasedTrophyIDs = cleaned
                self.me = meCopy
            }
        }
        // Auto-showcase the first three unlocked trophies so a fresh
        // profile has something to flex. Skips when the cached `me`
        // already has a user-picked showcase.
        let autoShowcase = trophies.filter { $0.isUnlocked }.prefix(3).map(\.stableKey)
        if !autoShowcase.isEmpty, var meCopy = me, meCopy.showcasedTrophyIDs.isEmpty {
            meCopy.showcasedTrophyIDs = Array(autoShowcase)
            self.me = meCopy
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

    /// Wipes the in-memory `me` row and forces the next `seed()` to
    /// rebuild from scratch instead of carrying over the previous
    /// signed-in user's profile. Called from AppState.signOut.
    func clearMe() {
        me = nil
        seeded = false
    }

    /// Re-derive workout-driven shelves (trophies, streak, PRs) from
    /// a fresh workouts list. seed() is called at launch with an
    /// empty workouts list (HealthKit hasn't loaded yet), so we have
    /// to refresh these shelves once the rehydrate completes.
    /// Otherwise trophies stay all-locked even when the user clearly
    /// has qualifying workouts.
    func refreshFromWorkouts(_ workouts: [Workout]) {
        trophies = Self.seedTrophies(workouts: workouts)
        streak = Self.seedStreak(workouts: workouts)
        personalRecords = PRCalculator.all(from: workouts)
    }

    /// Insert any user workouts that aren't already represented as a
    /// feed item — runs after every backfill so a workout finished
    /// while the app was backgrounded (e.g. a watch session that
    /// just synced) shows up at the top of the feed without forcing
    /// a relaunch. Critical for live demos: walk on stage → finish
    /// watch → return to app → workout appears + the "Claim Sweat"
    /// celebration is one tap away.
    func appendNewUserWorkouts(_ workouts: [Workout]) {
        guard let me else { return }
        // Workout ids the user already has a feed card for.
        let existing: Set<UUID> = Set(
            feed.compactMap { $0.athlete.id == me.id ? $0.workout.id : nil }
        )
        let fresh = workouts
            .filter { !existing.contains($0.id) }
            .sorted { $0.startDate > $1.startDate }
        guard !fresh.isEmpty else { return }
        let newItems: [FeedItem] = fresh.prefix(10).map { w in
            let hour = Calendar.current.component(.hour, from: w.startDate)
            return FeedItem(
                id: UUID(),
                athlete: me,
                workout: w,
                title: Self.defaultTitle(for: w, hour: hour),
                caption: nil,
                mapPreviewSeed: Int(abs(w.id.hashValue) % 1000),
                kudos: [],
                comments: [],
                userHasKudosed: false,
                tippedSweat: 0,
                taggedAthleteIDs: []
            )
        }
        feed.insert(contentsOf: newItems, at: 0)
        AppPersistence.saveFeed(feed)
    }

    /// Mark a claimable trophy as claimed and persist the key so the
    /// unlock survives a relaunch. Caller is responsible for ensuring
    /// the qualifying workout is on chain before calling this — see
    /// TrophyDetailSheet.claim() for the full flow.
    func markTrophyClaimed(stableKey: String) {
        guard let idx = trophies.firstIndex(where: { $0.stableKey == stableKey })
        else { return }
        var trophy = trophies[idx]
        // No-op if already unlocked, e.g. rapid double-tap.
        guard trophy.earnedAt == nil else { return }
        trophy.earnedAt = .now
        trophies[idx] = trophy

        var keys = AppPersistence.loadClaimedTrophyKeys()
        keys.insert(stableKey)
        AppPersistence.saveClaimedTrophyKeys(keys)
    }

    // MARK: - Live data refresh (Cloudflare API)
    //
    // Fetches feed + clubs + athletes + shoes + PRs in parallel. If any
    // call fails we keep the existing (seeded or stale) data — friends
    // testing should never see an empty screen because the network
    // hiccuped for a moment. Silent-on-error by design.

    var lastRefreshedAt: Date?
    var isRefreshing: Bool = false
    /// Set when the last refresh() errored out (network failure, 5xx, etc).
    /// FeedView shows a retry banner while this is true.
    var lastRefreshError: Bool = false
    /// Tracks whether we detected an offline condition during the last
    /// refresh (e.g. notConnectedToInternet). Used to tailor the banner
    /// copy and to know whether a retry has a chance of succeeding.
    var isOffline: Bool = false
    /// True when the last refresh failed with 401 (no/expired session).
    /// FeedView swaps the banner copy to "Sign in to load your feed."
    /// instead of the misleading "check your connection" message.
    var isUnauthorized: Bool = false

    /// Cursor for the next page of feed items, opaque "<key>:<id>"
    /// string from the server. `nil` = end of feed. Private to this
    /// service; views trigger loadMoreFeed() and observe feed.count
    /// growing.
    private var feedNextBefore: String?
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

    /// When true, `refresh()` returns early without hitting the
    /// server — the seeded fixture feed + clubs + athletes stay
    /// visible. Wired to `AppState.showDemoData` from RootTabView
    /// before each refresh.
    var demoOverride: Bool = false

    func refresh() async {
        guard !isRefreshing else { return }
        // Demo override: keep the seeded feed instead of hitting the
        // server. Used for stage demos where rich fixture data is
        // preferable to a freshly-signed-in empty feed.
        if demoOverride {
            lastRefreshError = false
            isOffline = false
            isUnauthorized = false
            lastRefreshedAt = .now
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        // Clear the auth-error flag at the top so a successful refresh
        // takes the banner away. We re-set it below if the new fetch
        // also 401s.
        isUnauthorized = false

        // Fetch the primary (feed) with an explicit do/catch so we can
        // classify offline vs server errors for the banner. Secondary
        // calls stay optional — a failing /shoes or /prs shouldn't
        // flag the whole refresh as errored.
        var feedEnv: FeedEnvelope?
        var refreshHadError = false
        var offlineDetected = false
        do {
            feedEnv = try await APIClient.shared.fetchFeedPage(sort: "recent", limit: 30)
        } catch let url as URLError {
            refreshHadError = true
            offlineDetected = [
                .notConnectedToInternet, .networkConnectionLost,
                .timedOut, .cannotFindHost, .cannotConnectToHost,
                .dataNotAllowed, .internationalRoamingOff
            ].contains(url.code)
        } catch let api as APIError {
            // Surface 401 distinctly so the feed banner can prompt the
            // user to sign in instead of suggesting a network problem.
            refreshHadError = true
            if case .server(let code, _) = api, code == 401 {
                isUnauthorized = true
            }
        } catch {
            refreshHadError = true
        }

        // Sequential rather than parallel — five concurrent URLSession
        // connections on launch saturate the per-host pool (default
        // ~6) and cause subsequent taps (kudos, tip, mint) to queue
        // for many seconds on flaky HTTP/3 paths. Running them in
        // sequence lets URLSession reuse one warmed connection, which
        // is much faster on bad networks and only marginally slower
        // on healthy ones.
        let fetchedClubs: [ClubDTO]? = try? await APIClient.shared.fetchClubs(filter: "all")
        let fetchedMe: AthleteDTO? = try? await APIClient.shared.fetchMe()
        let fetchedShoes: [ShoeDTO]? = try? await APIClient.shared.fetchShoes(athleteId: "0xdemo_me")
        let fetchedPRs: [PRDTO]? = try? await APIClient.shared.fetchPRs(athleteId: "0xdemo_me")

        if let env = feedEnv, !env.items.isEmpty {
            let items = env.items.map(FeedItem.init(dto:))
            feed = items
            feedItemApiIds = Dictionary(uniqueKeysWithValues:
                zip(items.map(\.id), env.items.map(\.id)))
            feedNextBefore = env.nextBefore
            // Harvest athletes from feed so profile taps resolve. Use a
            // dictionary keyed on id so repeat refreshes can't bloat
            // the list with duplicates of the same athlete — new ones
            // are appended, existing ones stay in their original slot.
            var byId: [String: Int] = [:]
            for (idx, a) in athletes.enumerated() { byId[a.id] = idx }
            for dto in env.items.map(\.athlete) {
                if byId[dto.id] == nil {
                    let a = Athlete(dto: dto)
                    byId[a.id] = athletes.count
                    athletes.append(a)
                }
            }
            // Persist top page + athletes so the next launch shows
            // real content immediately instead of waiting on /feed.
            AppPersistence.saveFeed(feed)
            AppPersistence.saveAthletes(athletes)
        }
        if let dtos = fetchedClubs, !dtos.isEmpty {
            let mapped = dtos.map(Club.init(dto:))
            clubs = mapped
            clubApiIds = Dictionary(uniqueKeysWithValues:
                zip(mapped.map(\.id), dtos.map(\.id)))
        }
        if let meDto = fetchedMe {
            // Merge instead of replace — preserves local-only fields
            // (photoData bytes for instant render, showcasedTrophyIDs)
            // that the server can't know about. Wholesale replace would
            // wipe the user's avatar bytes between launches.
            applyMePatch(meDto)
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
        lastRefreshError = refreshHadError
        isOffline = offlineDetected
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
        // Harvest athletes from the new page too — dedup on id so
        // repeat pages don't bloat the list.
        var byId: [String: Int] = [:]
        for (idx, a) in athletes.enumerated() { byId[a.id] = idx }
        for dto in env.items.map(\.athlete) {
            if byId[dto.id] == nil {
                let a = Athlete(dto: dto)
                byId[a.id] = athletes.count
                athletes.append(a)
            }
        }
        feedNextBefore = env.nextBefore
    }

    // MARK: - Actions (mutate local state, optimistic)

    func toggleKudos(on feedItemId: UUID) {
        guard let idx = feed.firstIndex(where: { $0.id == feedItemId }),
              let me else { return }
        var item = feed[idx]
        let liking = !item.userHasKudosed
        if item.userHasKudosed {
            item.kudos.removeAll { $0.athlete.id == me.id }
            item.userHasKudosed = false
        } else {
            item.kudos.insert(Kudos(id: UUID(), athlete: me, amountSweat: 0, at: .now), at: 0)
            item.userHasKudosed = true
        }
        feed[idx] = item
        let apiId = apiIdForFeedItem(feedItemId)
        if !apiId.isEmpty {
            Task.detached {
                try? await APIClient.shared.toggleKudos(
                    feedItemId: apiId, liked: liking
                )
            }
        }
    }

    /// After a successful on-chain mint, patch any feed items that
    /// wrap this workout so the verified strip flips from "Claim Sweat"
    /// to the on-chain link without needing a full refresh.
    func markFeedItemMinted(workoutId: UUID, digest: String, walrusBlobId: String?) {
        for idx in feed.indices where feed[idx].workout.id == workoutId {
            feed[idx].workout.suiTxDigest = digest
            feed[idx].workout.walrusBlobId = walrusBlobId
            feed[idx].workout.verified = true
        }
    }

    /// Append-only tip. Each call adds `amount` sweat to the item's
    /// running tipped_sweat total. Unlike kudos this never undoes —
    /// tipping is a positive-only action.
    func sendTip(on feedItemId: UUID, amount: Int = 1) {
        guard let idx = feed.firstIndex(where: { $0.id == feedItemId }) else { return }
        feed[idx].tippedSweat += amount
        let apiId = apiIdForFeedItem(feedItemId)
        if !apiId.isEmpty {
            Task.detached {
                try? await APIClient.shared.sendTip(feedItemId: apiId, amount: amount)
            }
        }
    }

    func addComment(_ body: String, to feedItemId: UUID) {
        guard let idx = feed.firstIndex(where: { $0.id == feedItemId }),
              let me else { return }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Optimistic insert. FeedItem.commentCount is derived from
        // comments.count so appending here bumps the visible count.
        let optimistic = Comment(
            id: UUID(), athlete: me, body: trimmed, at: .now, reactions: [:]
        )
        feed[idx].comments.append(optimistic)

        let apiId = apiIdForFeedItem(feedItemId)
        guard !apiId.isEmpty else { return }
        // Post to the server; on failure, roll back the optimistic
        // append on the MainActor so the local state stays consistent
        // with what the server sees.
        Task.detached { [weak self] in
            do {
                try await APIClient.shared.postComment(feedItemId: apiId, body: trimmed)
            } catch {
                await self?.rollbackOptimisticComment(commentId: optimistic.id,
                                                      feedItemId: feedItemId)
            }
        }
    }

    private func rollbackOptimisticComment(commentId: UUID, feedItemId: UUID) {
        guard let idx = feed.firstIndex(where: { $0.id == feedItemId }) else { return }
        feed[idx].comments.removeAll { $0.id == commentId }
    }

    /// Removes a feed item locally. Called after a successful DELETE
    /// /v1/workouts/<id> so the list updates without waiting for the
    /// next refresh.
    func remove(feedItemId: UUID) {
        feed.removeAll { $0.id == feedItemId }
        feedItemApiIds[feedItemId] = nil
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
        showcasedTrophyIDs: [String]? = nil,
        pronouns: String? = nil,
        websiteUrl: String? = nil,
        avatarR2Key: String? = nil
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
        if let v = pronouns {
            current.pronouns = v.trimmingCharacters(in: .whitespaces).isEmpty ? nil : v
        }
        if let v = websiteUrl {
            current.websiteUrl = v.trimmingCharacters(in: .whitespaces).isEmpty ? nil : v
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
        AppPersistence.saveMe(current)

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
            photoR2Key: nil,
            pronouns: pronouns,
            websiteUrl: websiteUrl,
            avatarR2Key: avatarR2Key
        )
        Task.detached { [weak self] in
            if let updated = try? await APIClient.shared.updateMe(patch) {
                await self?.applyMePatch(updated)
            }
        }
    }

    /// Merge a fresh AthleteDTO response into `me` without stomping on
    /// local-only UI state (photoData bytes, showcase selections). Called
    /// after a successful PATCH /v1/me so the server's canonical values
    /// (including any trimmed / normalized fields) land in the model.
    private func applyMePatch(_ dto: AthleteDTO) {
        guard var current = me else { return }
        current.displayName = dto.displayName
        current.handle = dto.handle
        current.bio = dto.bio
        current.location = dto.location
        current.pronouns = dto.pronouns
        current.websiteUrl = dto.websiteUrl
        current.photoURL = dto.photoURL
        if let tone = AvatarTone(rawValue: dto.avatarTone) { current.avatarTone = tone }
        if let tone = AvatarTone(rawValue: dto.bannerTone) { current.bannerTone = tone }
        self.me = current
        AppPersistence.saveMe(current)
        // Reconcile the server-side Sweat ledger into local state. Only
        // present after migration 0013 + worker deploy; absent values
        // are no-ops via the optional decode.
        AppState.shared?.reconcileSweatLedger(
            credited: dto.sweatCredited,
            redeemed: dto.sweatRedeemed
        )
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
        // ONE Championship roster seed.
        //
        // Bios + records cross-checked against onefc.com athlete pages
        // and Sherdog/Tapology where ONE's page didn't surface a
        // public record. Sources cited in the README brand &
        // licensing section.
        //
        // photoURL hotlinks ONE's public CDN. ONE Championship's content
        // syndication doc explicitly invites direct embedding from
        // their servers. The avatar view falls back to the gradient
        // initials view if any image 404s, so the demo never shows a
        // broken state. We attribute "Photo: ONE Championship" on the
        // athlete profile screen.
        return [
            oneFighter(
                handle: "yuya_wakamatsu", name: "Yuya Wakamatsu",
                tier: .legend, verified: true, tone: .ember,
                bio: "ONE Flyweight MMA World Champion. Pressure striker. Tribe Tokyo MMA. リトルピラーニャ.",
                location: "Tokyo, Japan",
                followers: 184_300, totalWorkouts: 612,
                photoURL: "https://cdn.onefc.com/wp-content/uploads/2025/03/Yuya_Wakamatsu-hero-champ-1200x1165-1-600x583.jpg"
            ),
            oneFighter(
                handle: "k1takeru", name: "Takeru Segawa",
                tier: .legend, verified: true, tone: .ember,
                bio: "Three-division K-1 champion. Natural Born Krusher. Team Vasileus. 武尊.",
                location: "Tokyo, Japan",
                followers: 1_240_000, totalWorkouts: 540,
                photoURL: "https://cdn.onefc.com/wp-content/uploads/2023/11/Takeru-1200x1165-1-600x583.png"
            ),
            oneFighter(
                handle: "nadaka", name: "Nadaka Yoshinari",
                tier: .legend, verified: true, tone: .grape,
                bio: "Inaugural ONE Atomweight Muay Thai World Champion. Pro debut at 14 in Lumpinee. Eiwa Sports Gym.",
                location: "Tokyo, Japan",
                followers: 88_400, totalWorkouts: 480,
                photoURL: "https://cdn.onefc.com/wp-content/uploads/2025/01/Nadaka-hero-champ-1200x1165-1-600x583.png"
            ),
            oneFighter(
                handle: "ayaka_zombie", name: "Ayaka Miura",
                tier: .gold, verified: true, tone: .rose,
                bio: "Atomweight grappler. 3rd-degree judo black belt. Inventor of the Ayaka Lock. Tribe Tokyo MMA.",
                location: "Tokyo, Japan",
                followers: 62_100, totalWorkouts: 410,
                photoURL: "https://cdn.onefc.com/wp-content/uploads/2023/10/Ayaka_Miura-hero-1200x1165-1-600x583.jpg"
            ),
            oneFighter(
                handle: "_itsuki_h_", name: "Itsuki Hirata",
                tier: .gold, verified: true, tone: .sunset,
                bio: "Android 18. Atomweight submission grappler. K-Clann Tokyo, training stints with Serra-Longo NY.",
                location: "Tokyo, Japan",
                followers: 96_800, totalWorkouts: 358,
                photoURL: "https://cdn.onefc.com/wp-content/uploads/2019/05/Itsuki_Hirata-hero-1200x1165-1-600x583.png"
            ),
            oneFighter(
                handle: "hiro_a_16", name: "Hiroki Akimoto",
                tier: .gold, verified: true, tone: .ocean,
                bio: "Karate-base bantamweight kickboxer. Body-shot specialist. Trains at Evolve MMA Singapore.",
                location: "Singapore",
                followers: 71_500, totalWorkouts: 502,
                photoURL: "https://cdn.onefc.com/wp-content/uploads/2019/01/Hiroki_Akimoto-hero-1200x1165-1-600x583.png"
            ),
            oneFighter(
                handle: "shinya050983", name: "Shinya Aoki",
                tier: .legend, verified: true, tone: .slate,
                bio: "Tobikan Judan. One of MMA's most decorated submission artists. Evolve MMA. Paraestra lineage.",
                location: "Singapore",
                followers: 318_000, totalWorkouts: 1_120,
                photoURL: "https://cdn.onefc.com/wp-content/uploads/2024/07/Shinya_Aoki-hero-1200x1165-1-600x583.png"
            ),
            oneFighter(
                handle: "tatsumitsu_wada", name: "Tatsumitsu Wada",
                tier: .silver, verified: true, tone: .forest,
                bio: "The Sweeper. Technical flyweight grappler. Two-time DEEP Flyweight Champion. Yoshida Dojo.",
                location: "Tokyo, Japan",
                followers: 24_400, totalWorkouts: 320,
                photoURL: "https://cdn.onefc.com/wp-content/uploads/2024/03/Tatsumitsu_Wada-hero-1200x1165-1-600x583.png"
            ),
        ]
    }

    /// Factory for an ONE Championship roster athlete. Wraps the rich
    /// seed data so the call sites in seedAthletes stay readable.
    private static func oneFighter(
        handle: String,
        name: String,
        tier: AthleteTier,
        verified: Bool,
        tone: AvatarTone,
        bio: String,
        location: String,
        followers: Int,
        totalWorkouts: Int,
        photoURL: String?
    ) -> Athlete {
        // Stable id per handle so SwiftUI list diffing survives
        // re-seeds.
        let localId = "one_\(handle)"
        return Athlete(
            id: localId,
            suiAddress: nil,
            handle: handle,
            displayName: name,
            avatarTone: tone,
            verified: verified,
            tier: tier,
            totalWorkouts: totalWorkouts,
            followers: followers,
            following: Int.random(in: 80...260),
            bio: bio,
            bannerTone: tone,
            photoData: nil,
            showcasedTrophyIDs: [],
            location: location,
            photoURL: photoURL
        )
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

        // ONE-themed feed copy. Captions echo what fighters actually
        // say in fight-week interviews — sharp, understated. Mix in a
        // few nil captions so not every card carries text.
        let captions = [
            "Six rounds, fresh legs. Camp's coming together.",
            "Pad work felt clean today. Coach happy.",
            "Roadwork before sunrise. Quiet streets, quiet mind.",
            "Drilled the lock until it stopped feeling like work.",
            "Sparring day. Walked out without a mark.",
            "Long run. Just thinking about Ariake.",
            nil,
            "Recovery + sauna. Cut starts Monday.",
            "Body shots, body shots, body shots.",
            "Clinch rounds with the boys. Filthy work.",
            nil,
            "Strength block, last heavy day before fight week.",
        ]

        // Workouts an ONE Championship fighter logs in camp. Striking
        // and grappling dominate; conditioning + roadwork fill the
        // rest; recovery is rare but visible.
        let fightTypes: [WorkoutType] = [
            .striking, .striking, .grappling, .mma, .conditioning,
            .striking, .grappling, .run, .recovery, .lift,
            .striking, .grappling
        ]

        var cursor = Date()
        for (i, athlete) in others.enumerated() {
            let dec = Double.random(in: 3*3600...48*3600)
            cursor = cursor.addingTimeInterval(-dec)
            let type: WorkoutType = fightTypes[i % fightTypes.count]
            let duration = Double.random(in: 1200...5400)
            // Distance only makes sense for roadwork-style activities;
            // striking / grappling sessions have no distance.
            let dist: Double? = (type == .run || type == .conditioning)
                ? Double.random(in: 4000...12000)
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
                    body: ["Sharp work 🔥", "Hands look fast", "See you at Ariake",
                           "Camp looks scary", "Filthy. Clinch is back.",
                           "Body shots are landing 👊", "OSU 🥋",
                           "Tip incoming", "Champ behavior"].randomElement() ?? "Sharp",
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
        // Real gyms in the ONE Championship orbit. Member counts /
        // weekly volumes are illustrative for the demo; gyms + their
        // affiliations are accurate (Evolve Singapore is ONE's home
        // gym; Tribe Tokyo is the Tokyo MMA hub; Team Vasileus is
        // Takeru's gym; Eiwa Sports Gym is Nadaka's home).
        return [
            Club(id: UUID(), name: "Evolve MMA — Singapore", handle: "evolvemma",
                 tagline: "Asia's premier MMA gym. Where ONE Champions train.",
                 description: "Home gym to a generation of ONE Champions including Aoki, Akimoto, and Christian Lee. Five locations across Singapore.",
                 heroTone: .ember, memberCount: 14_800, sweatTreasury: 612_000,
                 isJoined: true, isVerifiedBrand: true, weeklyKm: 0,
                 tags: ["mma", "muay thai", "bjj", "Singapore"], activeChallengeIDs: []),
            Club(id: UUID(), name: "Tribe Tokyo MMA", handle: "tribetokyo",
                 tagline: "Where Wakamatsu and Miura sharpen the blade.",
                 description: "Tokyo's high-pressure MMA room. Home of ONE Flyweight Champion Yuya Wakamatsu and atomweight grappler Ayaka Miura. Members-only sparring blocks Tuesday and Saturday.",
                 heroTone: .grape, memberCount: 1_240, sweatTreasury: 88_500,
                 isJoined: true, isVerifiedBrand: true, weeklyKm: 0,
                 tags: ["mma", "grappling", "Tokyo"], activeChallengeIDs: []),
            Club(id: UUID(), name: "Team Vasileus", handle: "team_vasileus",
                 tagline: "Takeru's home dojo. Krusher kickboxing.",
                 description: "Tokyo kickboxing dojo led by three-division K-1 champion Takeru Segawa. Pad rounds open to verified members on Wednesday nights.",
                 heroTone: .ember, memberCount: 980, sweatTreasury: 64_200,
                 isJoined: false, isVerifiedBrand: true, weeklyKm: 0,
                 tags: ["kickboxing", "Tokyo"], activeChallengeIDs: []),
            Club(id: UUID(), name: "Eiwa Sports Gym", handle: "eiwa_gym",
                 tagline: "Where Nadaka started at 14.",
                 description: "Saitama Muay Thai gym, training ground of ONE Atomweight Muay Thai Champion Nadaka. Pure Thai-style padwork.",
                 heroTone: .sunset, memberCount: 612, sweatTreasury: 22_400,
                 isJoined: false, isVerifiedBrand: false, weeklyKm: 0,
                 tags: ["muay thai", "Saitama"], activeChallengeIDs: []),
            Club(id: UUID(), name: "K-Clann", handle: "kclann",
                 tagline: "Itsuki Hirata's Tokyo grappling room.",
                 description: "K-Clann under Kazunori Yokota. Home base for atomweight submission specialist Itsuki Hirata.",
                 heroTone: .ocean, memberCount: 410, sweatTreasury: 14_900,
                 isJoined: false, isVerifiedBrand: false, weeklyKm: 0,
                 tags: ["mma", "grappling", "Tokyo"], activeChallengeIDs: []),
            Club(id: UUID(), name: "SuiSport ONE Founders' Circle", handle: "sui_core",
                 tagline: "The first fans on-chain.",
                 description: "Soulbound membership for the earliest fans to log a fighter-designed camp on SuiSport ONE. Founder-drop gear and monthly AMAs.",
                 heroTone: .slate, memberCount: 412, sweatTreasury: 55_000,
                 isJoined: true, isVerifiedBrand: true, weeklyKm: 0,
                 tags: ["community"], activeChallengeIDs: []),
        ]
    }

    static func seedChallenges() -> [Challenge] {
        let now = Date()
        let cal = Calendar.current
        func plus(_ d: Int) -> Date { cal.date(byAdding: .day, value: d, to: now) ?? now }
        func minus(_ d: Int) -> Date { cal.date(byAdding: .day, value: -d, to: now) ?? now }

        // Hackathon framing: every challenge is a fighter-designed
        // camp tied to ONE Samurai 1 (April 29, 2026, Ariake Arena).
        // The headline is the full fight-week camp — that's the demo
        // hero. Fighter-specific blocks underneath let users follow
        // a single athlete's program (Wakamatsu / Takeru / Ayaka /
        // Nadaka) and earn a soulbound trophy from that fighter on
        // completion.
        let one = Sponsor(name: "ONE Championship", handle: "onechampionship",
                          color: "#D90429")

        return [
            Challenge(
                id: UUID(), title: "ONE Samurai 1 — Fight Week",
                subtitle: "Complete the official fight-week camp with the Samurai card",
                kind: .workouts,
                sponsor: one,
                goal: ChallengeGoal(kind: .workouts, target: 14, unit: "sessions"),
                currentProgress: 0.0,
                startsAt: minus(2), endsAt: plus(5),
                stakeSweat: 100, prizePoolSweat: 250_000, participants: 8_412,
                isJoined: true, hero: .ember, badgeIcon: "trophy.fill",
                designerHandle: nil,
                trophyTitle: "Samurai 1 Fight Week Trophy",
                myRank: 1_204
            ),
            Challenge(
                id: UUID(), title: "Wakamatsu Pressure Camp",
                subtitle: "10 sessions, Yuya's flyweight pressure-striking block",
                kind: .workouts,
                sponsor: one,
                goal: ChallengeGoal(kind: .workouts, target: 10, unit: "sessions"),
                currentProgress: 0.30,
                startsAt: minus(7), endsAt: plus(14),
                stakeSweat: 50, prizePoolSweat: 88_000, participants: 2_104,
                isJoined: true, hero: .ember, badgeIcon: "figure.boxing",
                designerHandle: "yuya_wakamatsu",
                trophyTitle: "Yuya Pressure Camp Trophy",
                myRank: 312
            ),
            Challenge(
                id: UUID(), title: "Takeru Krusher 14",
                subtitle: "Fourteen days of K-1 conditioning + pad rounds",
                kind: .workouts,
                sponsor: one,
                goal: ChallengeGoal(kind: .workouts, target: 14, unit: "sessions"),
                currentProgress: 0.0,
                startsAt: plus(1), endsAt: plus(15),
                stakeSweat: 75, prizePoolSweat: 142_000, participants: 3_988,
                isJoined: false, hero: .grape, badgeIcon: "bolt.heart.fill",
                designerHandle: "k1takeru",
                trophyTitle: "Takeru Krusher Trophy",
                myRank: nil
            ),
            Challenge(
                id: UUID(), title: "Ayaka Submission Block",
                subtitle: "Atomweight grappling drills inspired by Tribe Tokyo",
                kind: .workouts,
                sponsor: one,
                goal: ChallengeGoal(kind: .workouts, target: 12, unit: "sessions"),
                currentProgress: 0.16,
                startsAt: minus(5), endsAt: plus(16),
                stakeSweat: 40, prizePoolSweat: 64_500, participants: 1_482,
                isJoined: false, hero: .rose, badgeIcon: "figure.wrestling",
                designerHandle: "ayaka_zombie",
                trophyTitle: "Ayaka Lock Trophy",
                myRank: nil
            ),
            Challenge(
                id: UUID(), title: "Nadaka Lumpinee Mile",
                subtitle: "30 days of pure Thai-style padwork + roadwork",
                kind: .workouts,
                sponsor: one,
                goal: ChallengeGoal(kind: .workouts, target: 30, unit: "sessions"),
                currentProgress: 0.07,
                startsAt: minus(3), endsAt: plus(27),
                stakeSweat: 60, prizePoolSweat: 96_400, participants: 1_812,
                isJoined: false, hero: .sunset, badgeIcon: "figure.martial.arts",
                designerHandle: "nadaka",
                trophyTitle: "Lumpinee Mile Trophy",
                myRank: nil
            ),
            Challenge(
                id: UUID(), title: "Roadwork Streak",
                subtitle: "Real fighters run. Log roadwork every day this week.",
                kind: .streak,
                sponsor: nil,
                goal: ChallengeGoal(kind: .streak, target: 7, unit: "days"),
                currentProgress: 0.71,
                startsAt: minus(5), endsAt: plus(2),
                stakeSweat: 25, prizePoolSweat: 18_240, participants: 3_221,
                isJoined: true, hero: .ocean, badgeIcon: "flame.fill",
                designerHandle: nil,
                trophyTitle: "Roadwork Streak Trophy",
                myRank: 488
            ),
        ]
    }

    static func seedSegments(others: [Athlete]) -> [Segment] {
        // Segments need at least one athlete to populate leaderboard
        // entries; bail with nothing rather than crash on the indexing
        // below if the roster has been wiped.
        guard !others.isEmpty else { return [] }
        // Hardcoded picks (kom/qom/legend slots) were originally tuned
        // to a 12-athlete roster. The ONE roster is shorter, so wrap
        // any index past the end back into range — keeps the seed
        // resilient if seedAthletes() grows or shrinks again.
        func at(_ i: Int) -> Athlete { others[i % others.count] }
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
                    kom: entry(at(2), 872), qom: entry(at(6), 942),
                    localLegend: legend(at(0)),
                    myBest: entry(at(3), 1160), myRank: 2_221,
                    starred: true, surface: .road, heroTone: .forest),
            Segment(id: UUID(), name: "Manhattan Bridge Climb",
                    location: "New York, NY",
                    distanceMeters: 720, elevationGainM: 33, avgGradePct: 4.6,
                    totalAttempts: 92_208, athleteCount: 18_442,
                    kom: entry(at(8), 126), qom: entry(at(10), 141),
                    localLegend: legend(at(4)),
                    myBest: entry(at(3), 172), myRank: 812,
                    starred: false, surface: .road, heroTone: .slate),
            Segment(id: UUID(), name: "Rockaway Flats TT",
                    location: "Queens, NY",
                    distanceMeters: 10_000, elevationGainM: 0, avgGradePct: 0,
                    totalAttempts: 12_420, athleteCount: 3_228,
                    kom: entry(at(8), 1482), qom: entry(at(11), 1604),
                    localLegend: legend(at(1)),
                    myBest: nil, myRank: nil,
                    starred: false, surface: .road, heroTone: .ocean),
            Segment(id: UUID(), name: "Bear Mountain Main",
                    location: "Hudson Valley, NY",
                    distanceMeters: 2400, elevationGainM: 210, avgGradePct: 8.8,
                    totalAttempts: 8_110, athleteCount: 2_088,
                    kom: entry(at(0), 518), qom: entry(at(6), 572),
                    localLegend: legend(at(7)),
                    myBest: nil, myRank: nil,
                    starred: true, surface: .trail, heroTone: .ember)
        ]
    }

    static func seedTrophies(workouts: [Workout]) -> [Trophy] {
        let totalKm = workouts.reduce(0.0) { $0 + ($1.distanceMeters ?? 0) / 1000 }
        let totalWorkouts = workouts.count
        let claimed = AppPersistence.loadClaimedTrophyKeys()

        // The qualifying workout becomes the on-chain payload when
        // the user claims, so it has to clear the server's Zod
        // bounds — anything that would 422 is functionally locked
        // for our flow even if it technically meets the criterion.
        // HealthKit aggregate rows occasionally come back with
        // 600km+ distance or absurd point totals; filter them out
        // here so we never pick one as the "qualifying" workout.
        //
        // Bounds mirror cloudflare/src/schemas/workouts.ts:
        //   distanceMeters ≤ 500_000 (500km)
        //   points         ≤ 10_000
        //   duration in    [60, 86_400] seconds
        func submittable(_ w: Workout) -> Bool {
            let d = w.distanceMeters ?? 0
            return d <= 500_000
                && w.points > 0
                && w.points <= 10_000
                && w.duration >= 60
                && w.duration <= 86_400
        }

        // Earliest workout overall (for "First Workout"). Filtered
        // to submittable so we don't pick a corrupted aggregate.
        let firstWorkout = workouts
            .filter(submittable)
            .min(by: { $0.startDate < $1.startDate })
        // Earliest qualifying run for each distance criterion. Earliest
        // (rather than longest) so we don't keep relabeling the same
        // marathon across runs after a longer one is added.
        func firstRun(distanceAtLeast meters: Double) -> Workout? {
            workouts
                .filter { ($0.distanceMeters ?? 0) >= meters && submittable($0) }
                .min(by: { $0.startDate < $1.startDate })
        }
        // Cumulative-distance trophies attribute to the workout that
        // pushed total over the threshold — chronologically the run
        // where the user "crossed" 100km. Skip the crossing workout
        // if it isn't submittable and try the next one that is, so
        // a corrupted aggregate doesn't lock the user out.
        func crossingWorkout(thresholdKm: Double) -> Workout? {
            var running = 0.0
            for w in workouts.sorted(by: { $0.startDate < $1.startDate }) {
                running += (w.distanceMeters ?? 0) / 1000
                if running >= thresholdKm && submittable(w) { return w }
            }
            return nil
        }

        func trophy(key: String, _ title: String, _ sub: String,
                    icon: String, rarity: Rarity, progress: Double,
                    cat: TrophyCategory, colors: [String],
                    qualifying: Workout?) -> Trophy {
            // Trophy state derives from two facts:
            //   1. Has the user done the qualifying work? -> qualifyingWorkoutId
            //   2. Have they tapped Claim? -> earnedAt
            let qualifyingId = qualifying?.id
            let earnedAt: Date? = claimed.contains(key) && qualifyingId != nil
                ? (qualifying?.startDate ?? .now)
                : nil
            return Trophy(
                id: UUID(),
                stableKey: key,
                title: title, subtitle: sub, icon: icon, rarity: rarity,
                earnedAt: earnedAt,
                progress: progress, category: cat,
                gradient: colors.map(hexColor),
                qualifyingWorkoutId: qualifyingId
            )
        }
        return [
            trophy(key: "first-workout",
                   "First Workout", "Logged your first session",
                   icon: "sparkles", rarity: .common,
                   progress: min(1, Double(totalWorkouts)),
                   cat: .firsts, colors: ["#A3FF70", "#0F6B38"],
                   qualifying: firstWorkout),
            trophy(key: "5k-finisher",
                   "5K Finisher", "Run 5 km in one workout",
                   icon: "figure.run.circle.fill", rarity: .common,
                   progress: min(1, firstRun(distanceAtLeast: 5000) != nil ? 1 : 0),
                   cat: .firsts, colors: ["#FFB020", "#FF5C2A"],
                   qualifying: firstRun(distanceAtLeast: 5000)),
            trophy(key: "10k-club",
                   "10K Club", "Run 10 km in one workout",
                   icon: "10.circle.fill", rarity: .rare,
                   progress: min(1, (workouts.compactMap { $0.distanceMeters }.max() ?? 0) / 10000),
                   cat: .firsts, colors: ["#45A9FF", "#275EC7"],
                   qualifying: firstRun(distanceAtLeast: 10000)),
            trophy(key: "half-marathon",
                   "Half Marathon", "Run 21.1 km in one workout",
                   icon: "figure.run", rarity: .epic,
                   progress: min(1, (workouts.compactMap { $0.distanceMeters }.max() ?? 0) / 21100),
                   cat: .firsts, colors: ["#B57BFF", "#5534BF"],
                   qualifying: firstRun(distanceAtLeast: 21100)),
            trophy(key: "first-marathon",
                   "First Marathon", "Finish a 42.2 km run",
                   icon: "trophy.fill", rarity: .legendary,
                   progress: min(1, (workouts.compactMap { $0.distanceMeters }.max() ?? 0) / 42195),
                   cat: .firsts, colors: ["#FFD246", "#E26C00"],
                   qualifying: firstRun(distanceAtLeast: 42195)),
            trophy(key: "100k-total",
                   "100k Total", "Run 100 km across all workouts",
                   icon: "chart.bar.fill", rarity: .rare,
                   progress: min(1, totalKm / 100),
                   cat: .distance, colors: ["#8CF0A3", "#1B7A3F"],
                   qualifying: crossingWorkout(thresholdKm: 100)),
            // Trophies below have no single qualifying workout —
            // they're driven by ongoing patterns (streaks, kudos
            // sent, season totals) so we pass `qualifying: nil`.
            // They render as truly locked until those patterns are
            // computed end-to-end (out of scope for the demo).
            trophy(key: "7-day-streak",
                   "7-Day Streak", "Work out 7 days in a row",
                   icon: "flame.fill", rarity: .rare, progress: 0.43,
                   cat: .streak, colors: ["#FF8A5C", "#C7321E"],
                   qualifying: nil),
            trophy(key: "30-day-streak",
                   "30-Day Streak", "Work out 30 days in a row",
                   icon: "flame.fill", rarity: .epic, progress: 0.12,
                   cat: .streak, colors: ["#FF3B8A", "#8B1044"],
                   qualifying: nil),
            trophy(key: "kudos-giver",
                   "Kudos Giver", "Send 100 kudos to friends",
                   icon: "hand.thumbsup.fill", rarity: .common, progress: 0.22,
                   cat: .social, colors: ["#9EE7FF", "#2B6EA3"],
                   qualifying: nil),
            trophy(key: "patron",
                   "Patron", "Tip 500 Sweat to other athletes",
                   icon: "heart.circle.fill", rarity: .epic, progress: 0.05,
                   cat: .social, colors: ["#FFB3D2", "#94325E"],
                   qualifying: nil),
            trophy(key: "april-100k",
                   "April 100k Finisher", "Hit 100 km in April",
                   icon: "medal.star.fill", rarity: .rare, progress: 0.42,
                   cat: .seasonal, colors: ["#F8D35B", "#AE6E1C"],
                   qualifying: nil),
            trophy(key: "nike-founders-drop",
                   "Nike Founders' Drop", "Early access to limited-edition Vaporfly",
                   icon: "bag.fill.badge.plus",
                   rarity: .legendary, progress: 0.0,
                   cat: .sponsor, colors: ["#1A1A1A", "#5A5A5A"],
                   qualifying: nil)
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

    /// Per-fighter community + posts. Hand-curated voice for the
    /// demo — Phase 2 moves authoring into a server tool. Cost is
    /// tier-derived via FighterCommunity.unlockCost(for:).
    static func seedCommunities(athletes: [Athlete]) -> [String: FighterCommunity] {
        var result: [String: FighterCommunity] = [:]
        let now = Date()
        func ago(_ days: Int) -> Date {
            Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        }
        for a in athletes where a.verified {
            let cost = FighterCommunity.unlockCost(for: a.tier)
            let posts = communityPosts(forHandle: a.handle, ago: ago)
            // Skip fighters we don't have curated posts for — better
            // to hide the tab than show an empty community.
            guard !posts.isEmpty else { continue }
            result[a.id] = FighterCommunity(
                id: a.id,
                unlockSweatCost: cost,
                requiredWorkoutType: workoutTypeFor(handle: a.handle),
                requiredWorkoutCount: 5,
                description: communityDescription(forHandle: a.handle, name: a.displayName),
                posts: posts
            )
        }
        return result
    }

    private static func workoutTypeFor(handle: String) -> String {
        switch handle {
        case "k1takeru":         return "striking"
        case "yuya_wakamatsu":   return "MMA"
        case "nadaka":           return "Muay Thai"
        default:                 return "training"
        }
    }

    private static func communityDescription(forHandle handle: String, name: String) -> String {
        switch handle {
        case "k1takeru":
            return "Behind-the-scenes from Takeru's camps — roadwork, pad sessions, fight-week mindset, and the occasional message straight to the community."
        case "yuya_wakamatsu":
            return "Tribe Tokyo MMA from the inside. Pressure-striking breakdowns, level-change drills, and Yuya's notes from camp."
        case "nadaka":
            return "Atomweight Muay Thai from a fighter who debuted in Lumpinee at 14. Clinch tactics, Eiwa drills, and Nadaka's diary."
        default:
            return "Posts, training tips, and behind-the-scenes from \(name)."
        }
    }

    private static func communityPosts(
        forHandle handle: String,
        ago: (Int) -> Date
    ) -> [CommunityPost] {
        switch handle {
        case "k1takeru":
            return [
                CommunityPost(
                    id: UUID(),
                    kind: .message,
                    title: "Personal message · fight week",
                    body: "Walking into Ariake with quiet feet. Coach's advice this week: don't bring the noise, become it. Watch the video — recorded between rounds yesterday.",
                    createdAt: ago(1),
                    youtubeURL: "https://www.youtube.com/watch?v=jLOcGuT-JAI",
                    isFreePreview: false
                ),
                CommunityPost(
                    id: UUID(),
                    kind: .trainingTip,
                    title: "Roadwork as round simulation",
                    body: "Pre-sunrise. Empty stomach. 5km tempo. The pain you feel at km 4 is the same pain you'll feel in round 3 — get used to it before fight night, not during.",
                    createdAt: ago(3),
                    youtubeURL: nil,
                    isFreePreview: true
                ),
                CommunityPost(
                    id: UUID(),
                    kind: .fightWeek,
                    title: "Camp wrap",
                    body: "Eight weeks closed out clean. Two more sessions of pad work, then I taper. Cuts start Monday — staying off social until walkout.",
                    createdAt: ago(6),
                    youtubeURL: nil,
                    isFreePreview: false
                ),
            ]
        case "yuya_wakamatsu":
            return [
                CommunityPost(
                    id: UUID(),
                    kind: .message,
                    title: "Camp update",
                    body: "Ariake training camp is grueling but the team is sharp. Two weeks out. Tribe Tokyo always shows up — this one feels different.",
                    createdAt: ago(2),
                    youtubeURL: nil,
                    isFreePreview: true
                ),
                CommunityPost(
                    id: UUID(),
                    kind: .trainingTip,
                    title: "Hide your level change",
                    body: "Drill the level change before the cross. Most fighters telegraph it because they reset their feet first. Anchor through the cross, then change levels off the rebound — same hip rotation, different exit.",
                    createdAt: ago(5),
                    youtubeURL: nil,
                    isFreePreview: false
                ),
                CommunityPost(
                    id: UUID(),
                    kind: .ama,
                    title: "AMA · weight cuts",
                    body: "Q: Hardest cut you've made?  A: Going to flyweight in 2019. Lost 8 kg in three weeks. Won't do that again — the bike sessions almost broke me. These days I cut from 5 weeks out, no last-mile sauna.",
                    createdAt: ago(8),
                    youtubeURL: nil,
                    isFreePreview: false
                ),
            ]
        case "nadaka":
            return [
                CommunityPost(
                    id: UUID(),
                    kind: .message,
                    title: "Birthday training",
                    body: "Birthday session. 14 years old in Lumpinee — first pro fight. 25 today. Same fire, more sense. Eiwa Sports Gym never changes.",
                    createdAt: ago(2),
                    youtubeURL: nil,
                    isFreePreview: true
                ),
                CommunityPost(
                    id: UUID(),
                    kind: .trainingTip,
                    title: "Clinch isn't strength",
                    body: "Clinch isn't about strength. It's about reading where their weight is, then putting yours on top of it. Drill from neutral, drill from inferior. Strength makes you tired; position makes you dangerous.",
                    createdAt: ago(4),
                    youtubeURL: nil,
                    isFreePreview: false
                ),
            ]
        default:
            return []
        }
    }

    /// Per-fighter training camps. 5 sessions each, sequenced like a
    /// real fight-camp microcycle: skill / sparring / conditioning /
    /// recovery. Hand-curated voice for the demo — Phase 2 moves
    /// authoring to a server tool.
    static func seedTrainingPlans(athletes: [Athlete]) -> [String: FighterTrainingPlan] {
        var result: [String: FighterTrainingPlan] = [:]
        for a in athletes where a.verified {
            guard let plan = trainingPlanForHandle(a.handle, athleteId: a.id) else { continue }
            result[a.id] = plan
        }
        return result
    }

    /// Single placeholder video used across every demo session. Phase
    /// 2 swaps these for per-fighter, per-session footage; for the
    /// hackathon demo a known-good URL keeps the embed safe from 404s.
    /// (User-supplied earlier as Takeru's community post video.)
    private static let placeholderVideoURL =
        "https://www.youtube.com/watch?v=jLOcGuT-JAI"

    private static func trainingPlanForHandle(_ handle: String, athleteId: String) -> FighterTrainingPlan? {
        switch handle {
        case "k1takeru":
            return FighterTrainingPlan(
                id: athleteId,
                title: "Takeru's Fight Camp",
                subtitle: "Three-division K-1 striking, distilled into 5 sessions.",
                sessions: [
                    TrainingSession(
                        stableKey: "takeru-1", index: 0,
                        title: "Pre-sunrise roadwork",
                        summary: "5 km tempo run on empty stomach. Round-3-pain conditioning.",
                        workoutType: "run", targetMinutes: 30, intensity: .moderate,
                        steps: [
                            "Warm up: 5 min easy jog + dynamic leg swings.",
                            "Build: 5 × 30-second strides at race pace, 90s easy between.",
                            "Tempo: 5 km at conversational-but-uncomfortable pace.",
                            "Last km: pick up to 80% — practice closing rounds tired.",
                            "Cool down: 5 min walk + box-breathing (4-4-4-4)."
                        ],
                        videoURL: placeholderVideoURL
                    ),
                    TrainingSession(
                        stableKey: "takeru-2", index: 1,
                        title: "Heavy bag rounds",
                        summary: "Round-based heavy bag work — pressure striking with footwork and breath control.",
                        workoutType: "striking", targetMinutes: 35, intensity: .hard,
                        steps: [
                            "Wraps on, gloves on. Warm shoulders with 3 minutes of skip rope or shadow.",
                            "Set a round timer: 3 minutes work, 30 seconds rest. Plan for 6 rounds.",
                            "Round 1-2: jab-cross repetition. Stay tall, exhale on every punch.",
                            "Round 3-4: add the low kick at the end of every combo. Work both sides.",
                            "Round 5-6: free flow. Vary tempo — slow-fast-slow inside each round.",
                            "Reset between rounds: shake out the arms, breathe through the nose.",
                            "Cool down: 30 lateral slips around the bag, then stretch the lats and hips."
                        ],
                        videoURL: "https://www.youtube.com/watch?v=AGQi8lVISoI"
                    ),
                    TrainingSession(
                        stableKey: "takeru-3", index: 2,
                        title: "Live sparring",
                        summary: "5 × 3-minute rounds. Walk out without a mark.",
                        workoutType: "striking", targetMinutes: 25, intensity: .peak,
                        steps: [
                            "Glove up: 16oz minimum, mouthguard, shin pads.",
                            "Round 1-2: technical sparring at 50% — clean exchanges only.",
                            "Round 3: 70% pace, feet active, cut angles.",
                            "Round 4-5: full pace, partner picks up the heat.",
                            "After: 10 min light flow rolling, no power."
                        ],
                        videoURL: placeholderVideoURL
                    ),
                    TrainingSession(
                        stableKey: "takeru-4", index: 3,
                        title: "Conditioning circuit",
                        summary: "Engine work — sprints, kettlebells, jump rope. Six rounds.",
                        workoutType: "hiit", targetMinutes: 30, intensity: .hard,
                        steps: [
                            "Warm up: 5 min easy bike or jog.",
                            "Round (4 min on, 1 min off) × 6:",
                            "  • 60s burpees · 60s KB swings · 60s jump rope · 60s mountain climbers",
                            "Hold steady through round 4. Earn round 5-6.",
                            "Finisher: 50 squats unbroken, then walk it out."
                        ],
                        videoURL: placeholderVideoURL
                    ),
                    TrainingSession(
                        stableKey: "takeru-5", index: 4,
                        title: "Recovery + mobility",
                        summary: "Sauna, foam roll, hip mobility. Cut-week move.",
                        workoutType: "recovery", targetMinutes: 25, intensity: .easy,
                        steps: [
                            "Foam roll: quads, glutes, lats — 60s each, both sides.",
                            "Hip 90/90: 8 reps each side, 3 sets, slow.",
                            "Cossack squats: 10 reps × 3 — open the groin.",
                            "Box breathing: 4 min, eyes closed.",
                            "Sauna or hot bath: 15 min if available."
                        ],
                        videoURL: placeholderVideoURL
                    ),
                ]
            )
        case "yuya_wakamatsu":
            return FighterTrainingPlan(
                id: athleteId,
                title: "Yuya's Tribe Tokyo Camp",
                subtitle: "MMA pressure-striking + grappling, 5 sessions.",
                sessions: [
                    TrainingSession(
                        stableKey: "yuya-1", index: 0,
                        title: "Striking pad work",
                        summary: "Hide the level change inside the cross. Six rounds.",
                        workoutType: "striking", targetMinutes: 30, intensity: .hard,
                        steps: [
                            "Skip rope: 2 × 3-min rounds.",
                            "Shadow: 2 rounds with level changes every 4-5 strikes.",
                            "Pads: 6 × 3-min. Combo: jab-cross-LEVEL CHANGE-cross.",
                            "Anchor through the cross — don't reset feet first.",
                            "Round 5-6: coach calls level change at random.",
                            "Cool down: 2 min easy bag, deep breaths."
                        ],
                        videoURL: placeholderVideoURL
                    ),
                    TrainingSession(
                        stableKey: "yuya-2", index: 1,
                        title: "Grappling drills",
                        summary: "Wrestling shots from neutral, scrambles, double-leg defense.",
                        workoutType: "grappling", targetMinutes: 30, intensity: .hard,
                        steps: [
                            "Warm up: bear crawls, sprawls, hip escapes — 5 min.",
                            "Drill: double-leg shot, 25 reps each side.",
                            "Drill: sprawl-and-spin defense, 20 reps each side.",
                            "Live: 4 × 2-min positional rounds from neutral.",
                            "Cool down: 5 min light technical flow."
                        ],
                        videoURL: placeholderVideoURL
                    ),
                    TrainingSession(
                        stableKey: "yuya-3", index: 2,
                        title: "MMA sparring",
                        summary: "5 × 3-min mixed rounds. Standup to clinch to ground.",
                        workoutType: "mma", targetMinutes: 25, intensity: .peak,
                        steps: [
                            "Glove up: MMA gloves, mouthguard, shin pads.",
                            "Round 1-2: stand-up only, 60% pace.",
                            "Round 3: stand-up to clinch transitions allowed.",
                            "Round 4-5: full MMA. Take it down if the shot's clean.",
                            "After: 5 min cool-down flow rolling, breathe slow."
                        ],
                        videoURL: placeholderVideoURL
                    ),
                    TrainingSession(
                        stableKey: "yuya-4", index: 3,
                        title: "Conditioning roadwork",
                        summary: "6 km tempo, last km at race pace.",
                        workoutType: "run", targetMinutes: 35, intensity: .moderate,
                        steps: [
                            "5 min easy warm-up jog.",
                            "5 km steady tempo — should feel like fight-week pace.",
                            "Final km: pick up to 85%. Stay tall, drive arms.",
                            "5 min cool-down walk + breath work.",
                            "Hydrate immediately on return."
                        ],
                        videoURL: placeholderVideoURL
                    ),
                    TrainingSession(
                        stableKey: "yuya-5", index: 4,
                        title: "Recovery session",
                        summary: "Mobility + light technical drilling. Brain off, body on.",
                        workoutType: "recovery", targetMinutes: 20, intensity: .easy,
                        steps: [
                            "Foam roll: 5 min full-body.",
                            "10 min light shadow work — keep heart rate low.",
                            "5 min stretch: hips, shoulders, lats.",
                            "Box breathing 4 min — close the day."
                        ],
                        videoURL: placeholderVideoURL
                    ),
                ]
            )
        case "nadaka":
            return FighterTrainingPlan(
                id: athleteId,
                title: "Nadaka's Eiwa Camp",
                subtitle: "Atomweight Muay Thai with the Lumpinee mindset, 5 sessions.",
                sessions: [
                    TrainingSession(
                        stableKey: "nadaka-1", index: 0,
                        title: "Clinch drills",
                        summary: "Read where their weight is, put yours on top of it.",
                        workoutType: "grappling", targetMinutes: 25, intensity: .hard,
                        steps: [
                            "Warm up: neck rolls, shoulder pulls — 5 min.",
                            "Drill: hand-fight to inside-tie, 20 reps each side.",
                            "Drill: knee-from-clinch, 15 reps each side.",
                            "Drill: clinch sweep off pummel, 10 reps each side.",
                            "Live: 3 × 2-min clinch rounds, technical pace."
                        ],
                        videoURL: placeholderVideoURL
                    ),
                    TrainingSession(
                        stableKey: "nadaka-2", index: 1,
                        title: "Pad rounds",
                        summary: "Long combos with knee finishes.",
                        workoutType: "striking", targetMinutes: 30, intensity: .hard,
                        steps: [
                            "Skip rope: 3 × 3-min rounds.",
                            "Shadow: 2 rounds, knee-up footwork.",
                            "Pads: 6 × 3-min. Combo: jab-cross-elbow-knee.",
                            "Round 4+: cross-step into clinch knee.",
                            "Cool down: 50 alternating push kicks, breathe."
                        ],
                        videoURL: placeholderVideoURL
                    ),
                    TrainingSession(
                        stableKey: "nadaka-3", index: 2,
                        title: "Light sparring",
                        summary: "Cleaner exchanges, no headhunting.",
                        workoutType: "striking", targetMinutes: 25, intensity: .peak,
                        steps: [
                            "Glove up: 14-16oz, no shin pads, control intent.",
                            "5 × 3-min sparring rounds at 50-60%.",
                            "Focus: setup the knee with hands first.",
                            "If a clinch happens, drill the break — don't dwell.",
                            "Walk out smiling. No one wins, you both train."
                        ],
                        videoURL: placeholderVideoURL
                    ),
                    TrainingSession(
                        stableKey: "nadaka-4", index: 3,
                        title: "Roadwork",
                        summary: "Quiet streets, quiet mind. 5 km nose-breathing.",
                        workoutType: "run", targetMinutes: 30, intensity: .moderate,
                        steps: [
                            "Choose a route you know. Phone on Do Not Disturb.",
                            "5 min easy warm-up.",
                            "5 km easy pace — nose-breathe the entire run.",
                            "If you can't nose-breathe, slow down.",
                            "Cool down: 5 min walk, no headphones."
                        ],
                        videoURL: placeholderVideoURL
                    ),
                    TrainingSession(
                        stableKey: "nadaka-5", index: 4,
                        title: "Recovery + stretch",
                        summary: "Hot bath, deep stretch, journal one thing learned.",
                        workoutType: "recovery", targetMinutes: 20, intensity: .easy,
                        steps: [
                            "Hot bath or sauna: 10 min if available.",
                            "Hip flexor stretch: 60s each side, 3 sets.",
                            "Pigeon stretch: 90s each side.",
                            "Lats + thoracic spine: 60s each.",
                            "Journal: write down one thing you learned this camp."
                        ],
                        videoURL: placeholderVideoURL
                    ),
                ]
            )
        default:
            return nil
        }
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
