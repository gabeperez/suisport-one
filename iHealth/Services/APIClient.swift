import Foundation

/// Thin client to the SuiSport backend (Cloudflare Worker + D1 + R2).
///
/// The backend is the abstraction layer over Enoki (zkLogin), Walrus
/// (storage), and Sui (programmable transactions + sponsored gas). The iOS
/// app never talks to Sui or Walrus directly — it hits this API with a
/// session token and an App Attest assertion on mutating calls.
///
/// All decoded DTOs expose an `isDemo` flag so the UI can visually mark
/// seeded data if we ever want to. `DemoData` badge support lives in the
/// design system.
nonisolated final class APIClient: @unchecked Sendable {
    static let shared = APIClient()

    let baseURL: URL = URL(string: "https://suisport-api.perez-jg22.workers.dev/v1")!

    /// Session token returned by `/auth/session`. While we mock the auth
    /// flow, we fall back to a `demoAthleteId` query param so the API
    /// accepts mutating calls without a real session.
    /// Bearer JWT issued by /v1/auth/session. Hydrated from Keychain
    /// at construction; assigning a new value (or nil) writes through
    /// so the next launch picks up the change.
    var sessionToken: String? = AppPersistence.loadSessionToken() {
        didSet { AppPersistence.saveSessionToken(sessionToken) }
    }
    var demoAthleteId: String? = "0xdemo_me"

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        // Tight timeout so a stuck QUIC handshake (seen on iOS sim
        // cellular paths with no UDP) gives up fast and the retry
        // path in send() can take over with a fresh connection.
        cfg.timeoutIntervalForRequest = 8
        cfg.timeoutIntervalForResource = 20
        cfg.waitsForConnectivity = true
        // HTTP/3 pipelining is what hangs on simulator. Default
        // multipath service forces a more conservative path.
        cfg.multipathServiceType = .none
        return URLSession(configuration: cfg)
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .useDefaultKeys   // server already emits camelCase
        return d
    }()

    // MARK: - Auth

    /// POST /auth/session { provider, idToken, displayName } → { sessionJwt, suiAddress, displayName }
    func exchange(provider: AuthProvider, idToken: String, displayName: String?) async throws -> AuthExchangeResponse {
        try await post(
            "/auth/session",
            body: AuthExchangeRequest(
                provider: provider.rawValue,
                idToken: idToken,
                displayName: displayName
            )
        )
    }

    // MARK: - Profile

    func fetchMe() async throws -> AthleteDTO { (try await get("/me") as AthleteEnvelope).athlete }

    func updateMe(_ body: AthletePatch) async throws -> AthleteDTO {
        (try await sendPatch("/me", body: body) as AthleteEnvelope).athlete
    }

    func fetchAthlete(id: String) async throws -> AthleteDTO {
        (try await get("/athletes/\(id)") as AthleteEnvelope).athlete
    }

    // MARK: - Media

    /// POST /v1/media/avatar (raw body). Server accepts image/jpeg,
    /// image/png, or image/webp up to 5 MB and returns the public URL
    /// plus the stable R2 key. Stash the key in an AthletePatch to
    /// associate the upload with the signed-in athlete.
    func uploadAvatar(data: Data, mime: String) async throws -> (url: String, r2Key: String) {
        var req = URLRequest(url: urlFor("/media/avatar"))
        req.httpMethod = "POST"
        req.setValue(mime, forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = sessionToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = data
        let resp: AvatarUploadResponse = try await send(req)
        return (resp.url, resp.r2Key)
    }

    // MARK: - Feed

    /// Returns one page of feed items + the cursor for the next page.
    /// Pass `before = nil` for the first page; pass the returned
    /// `nextBefore` to fetch older items. `nextBefore == nil` on the
    /// response = end of feed. The cursor is an opaque string shaped
    /// `"<ordering-key>:<feed-item-id>"` — the server uses the id as a
    /// tiebreaker so concurrent inserts/deletes can't cause phantom
    /// or duplicate items across pages.
    func fetchFeedPage(sort: String = "recent", limit: Int = 30,
                       before: String? = nil) async throws -> FeedEnvelope {
        var path = "/feed?sort=\(sort)&limit=\(limit)"
        if let before, !before.isEmpty {
            let encoded = before.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? before
            path += "&before=\(encoded)"
        }
        return try await get(path)
    }

    /// Legacy single-page fetch used by the initial refresh path.
    /// Prefer fetchFeedPage() for anything that needs pagination.
    func fetchFeed(sort: String = "recent", limit: Int = 50) async throws -> [FeedItemDTO] {
        try await fetchFeedPage(sort: sort, limit: limit).items
    }

    func toggleKudos(feedItemId: String, liked: Bool) async throws {
        if liked {
            _ = try await postVoid("/feed/\(feedItemId)/kudos", body: EmptyBody())
        } else {
            _ = try await deleteVoid("/feed/\(feedItemId)/kudos")
        }
    }

    func sendTip(feedItemId: String, amount: Int = 1) async throws {
        _ = try await postVoid("/feed/\(feedItemId)/tip", body: ["amount": amount])
    }

    func postComment(feedItemId: String, body text: String) async throws {
        _ = try await postVoid("/feed/\(feedItemId)/comments", body: ["body": text])
    }

    func muteAthlete(id: String) async throws {
        _ = try await postVoid("/mute/\(id)", body: EmptyBody())
    }

    func unmute(athleteId: String) async throws {
        _ = try await deleteVoid("/mute/\(athleteId)")
    }

    func deleteComment(feedItemId: String, commentId: String) async throws {
        _ = try await deleteVoid("/feed/\(feedItemId)/comments/\(commentId)")
    }

    func report(feedItemId: String?, athleteId: String?, reason: String) async throws {
        _ = try await postVoid("/report", body: ReportRequest(
            feedItemId: feedItemId, athleteId: athleteId, reason: reason
        ))
    }

    // MARK: - Clubs

    func fetchClubs(filter: String = "all") async throws -> [ClubDTO] {
        (try await get("/clubs?filter=\(filter)") as ClubsEnvelope).clubs
    }

    func createClub(_ req: CreateClubRequest) async throws -> String {
        (try await post("/clubs", body: req) as IdEnvelope).id
    }

    func joinClub(id: String) async throws {
        _ = try await postVoid("/clubs/\(id)/membership", body: EmptyBody())
    }

    func leaveClub(id: String) async throws {
        _ = try await deleteVoid("/clubs/\(id)/membership")
    }

    // MARK: - Challenges / segments

    func fetchChallenges() async throws -> [ChallengeDTO] {
        (try await get("/challenges") as ChallengesEnvelope).challenges
    }

    func fetchSegments() async throws -> [SegmentDTO] {
        (try await get("/segments") as SegmentsEnvelope).segments
    }

    // MARK: - Trophies / shoes / PRs

    func fetchTrophies(athleteId: String) async throws -> [TrophyDTO] {
        (try await get("/athletes/\(athleteId)/trophies") as TrophiesEnvelope).trophies
    }

    func fetchShoes(athleteId: String) async throws -> [ShoeDTO] {
        (try await get("/athletes/\(athleteId)/shoes") as ShoesEnvelope).shoes
    }

    func addShoe(_ req: AddShoeRequest) async throws -> String {
        (try await post("/shoes", body: req) as IdEnvelope).id
    }

    func fetchPRs(athleteId: String) async throws -> [PRDTO] {
        (try await get("/athletes/\(athleteId)/prs") as PRsEnvelope).prs
    }

    // MARK: - Sweat / streak

    func fetchSweat(athleteId: String) async throws -> SweatEnvelope {
        try await get("/athletes/\(athleteId)/sweat")
    }

    // MARK: - Workouts

    func submitWorkout(_ req: SubmitWorkoutRequest) async throws -> SubmitWorkoutResponse {
        try await post("/workouts", body: req)
    }

    func deleteWorkout(id: String) async throws {
        _ = try await deleteVoid("/workouts/\(id)")
    }

    // MARK: - Auth diagnostics

    func fetchWhoami() async throws -> WhoamiResponse { try await get("/auth/whoami") }

    // MARK: - Wallet auth

    func walletChallenge() async throws -> WalletChallengeResponse {
        try await post("/auth/wallet/challenge", body: EmptyBody())
    }

    func walletVerify(challengeId: String, address: String, signature: String) async throws -> AuthExchangeResponse {
        try await post("/auth/wallet/verify", body: WalletVerifyRequest(
            challengeId: challengeId, address: address, signature: signature
        ))
    }

    // MARK: - Sui / on-chain

    func fetchSuiStatus() async throws -> SuiStatusResponse { try await get("/sui/status") }

    func fetchSweatBalance(address: String) async throws -> SweatBalanceResponse {
        try await get("/sui/balance/\(address)")
    }

    func fetchWorkoutOnChain(workoutId: String) async throws -> WorkoutOnChainResponse {
        try await get("/workouts/\(workoutId)/onchain")
    }

    // MARK: - Rewards

    func fetchRewardsCatalog() async throws -> [RewardCatalogItemDTO] {
        (try await get("/rewards/catalog") as RewardsCatalogEnvelope).items
    }

    func redeemReward(catalogId: String) async throws -> RedemptionResponse {
        try await post("/rewards/redeem", body: ["catalogId": catalogId])
    }

    /// Sample on-chain redemption: spends 1 Sweat off-chain, sponsors a
    /// 0.001 SUI transfer from operator → user as the on-chain receipt.
    /// Drives the demo's "redemption is wired into Sui" moment.
    func redeemSample() async throws -> SampleRedemptionResponse {
        try await post("/rewards/redeem-sample", body: EmptyBody())
    }

    func fetchRewardsHistory() async throws -> [RedemptionHistoryItemDTO] {
        (try await get("/rewards/history") as RewardsHistoryEnvelope).items
    }

    // MARK: - Health

    func health() async throws -> HealthResponse { try await get("/../health") }

    // MARK: - Internals

    private func urlFor(_ path: String) -> URL {
        // `/../health` is a hack to escape the /v1 prefix. Strip and rejoin.
        if path.hasPrefix("/../") {
            let stripped = String(path.dropFirst(4))
            return baseURL.deletingLastPathComponent().appendingPathComponent(stripped)
        }
        var comps = URLComponents(url: baseURL.appending(path: path),
                                  resolvingAgainstBaseURL: false)!
        // Append demo athlete id on the request so the server knows who's asking
        // during mock-auth. Drop this when real sessions are wired.
        if sessionToken == nil, let demo = demoAthleteId {
            let item = URLQueryItem(name: "athleteId", value: demo)
            comps.queryItems = (comps.queryItems ?? []) + [item]
        }
        return comps.url!
    }

    private func makeRequest(_ method: String, _ path: String, body: Data? = nil) -> URLRequest {
        var req = URLRequest(url: urlFor(path))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body { req.setValue("application/json", forHTTPHeaderField: "Content-Type"); req.httpBody = body }
        if let token = sessionToken { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return req
    }

    private func send<T: Decodable>(_ req: URLRequest, attempt: Int = 1) async throws -> T {
        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw APIError.transport(URLError(.badServerResponse)) }
            if http.statusCode == 401 {
                sessionToken = nil    // Session dead, fall back to demo
                throw APIError.server(401, "unauthorized")
            }
            if (500..<600).contains(http.statusCode) && attempt == 1 {
                try await Task.sleep(nanoseconds: 400_000_000)
                return try await send(req, attempt: 2)
            }
            if !(200..<300).contains(http.statusCode) {
                let msg = String(data: data, encoding: .utf8) ?? ""
                throw APIError.server(http.statusCode, msg)
            }
            return try decoder.decode(T.self, from: data)
        } catch let error as URLError where attempt == 1 &&
            [.timedOut, .networkConnectionLost, .notConnectedToInternet].contains(error.code) {
            try await Task.sleep(nanoseconds: 400_000_000)
            return try await send(req, attempt: 2)
        }
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try await send(makeRequest("GET", path))
    }

    private func post<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        let data = try JSONEncoder().encode(body)
        return try await send(makeRequest("POST", path, body: data))
    }

    private func postVoid<B: Encodable>(_ path: String, body: B) async throws -> EmptyResponse {
        let data = try JSONEncoder().encode(body)
        return try await send(makeRequest("POST", path, body: data))
    }

    private func sendPatch<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        let data = try JSONEncoder().encode(body)
        return try await send(makeRequest("PATCH", path, body: data))
    }

    private func deleteVoid(_ path: String) async throws -> EmptyResponse {
        try await send(makeRequest("DELETE", path))
    }
}

// MARK: - Errors

enum APIError: Error {
    case notImplemented
    case transport(Error)
    case server(Int, String)
}

// MARK: - DTOs (match the Worker's db.ts mappers one-to-one)

nonisolated struct AthleteDTO: Decodable, Hashable {
    let id: String                // user_id (server-assigned UUID)
    let suiAddress: String?       // Sui chain address, if signed in via zkLogin
    let handle: String
    let displayName: String
    let avatarTone: String
    let bannerTone: String
    let verified: Bool
    let tier: String
    let totalWorkouts: Int
    let followers: Int
    let following: Int
    let bio: String?
    let location: String?
    let photoURL: String?
    let suinsName: String?
    /// Unix seconds at start-of-day UTC (or any server-stored instant); nil if unset.
    let dob: TimeInterval?
    let isDemo: Bool
    // Extended profile fields. All optional so older server builds still
    // decode cleanly — if the server doesn't ship them they stay nil.
    let pronouns: String?
    let websiteUrl: String?
    /// Lifetime Sweat credited (display units) — server ledger from
    /// migration 0013. Optional so a not-yet-deployed server still
    /// decodes cleanly.
    let sweatCredited: Int?
    /// Lifetime Sweat redeemed across all redemption flows.
    let sweatRedeemed: Int?

    private enum CodingKeys: String, CodingKey {
        case id, suiAddress, handle, displayName, avatarTone, bannerTone,
             verified, tier, totalWorkouts, followers, following, bio,
             location, photoURL, suinsName, dob, isDemo, pronouns, websiteUrl,
             sweatCredited, sweatRedeemed
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.suiAddress = try c.decodeIfPresent(String.self, forKey: .suiAddress)
        self.handle = try c.decode(String.self, forKey: .handle)
        self.displayName = try c.decode(String.self, forKey: .displayName)
        self.avatarTone = try c.decode(String.self, forKey: .avatarTone)
        self.bannerTone = try c.decode(String.self, forKey: .bannerTone)
        self.verified = try c.decode(Bool.self, forKey: .verified)
        self.tier = try c.decode(String.self, forKey: .tier)
        self.totalWorkouts = try c.decode(Int.self, forKey: .totalWorkouts)
        self.followers = try c.decode(Int.self, forKey: .followers)
        self.following = try c.decode(Int.self, forKey: .following)
        self.bio = try c.decodeIfPresent(String.self, forKey: .bio)
        self.location = try c.decodeIfPresent(String.self, forKey: .location)
        self.photoURL = try c.decodeIfPresent(String.self, forKey: .photoURL)
        self.suinsName = try c.decodeIfPresent(String.self, forKey: .suinsName)
        self.dob = try c.decodeIfPresent(TimeInterval.self, forKey: .dob)
        self.isDemo = try c.decode(Bool.self, forKey: .isDemo)
        self.pronouns = try c.decodeIfPresent(String.self, forKey: .pronouns)
        self.websiteUrl = try c.decodeIfPresent(String.self, forKey: .websiteUrl)
        self.sweatCredited = try c.decodeIfPresent(Int.self, forKey: .sweatCredited)
        self.sweatRedeemed = try c.decodeIfPresent(Int.self, forKey: .sweatRedeemed)
    }
}
nonisolated struct AthleteEnvelope: Decodable { let athlete: AthleteDTO }

nonisolated struct WorkoutDTO: Decodable, Hashable {
    let id: String
    let athleteId: String
    let type: String
    let startDate: TimeInterval
    let durationSeconds: TimeInterval
    let distanceMeters: Double?
    let energyKcal: Double?
    let avgHeartRate: Double?
    let paceSecondsPerKm: Double?
    let points: Int
    let verified: Bool
    let isDemo: Bool
    /// Sui tx digest for this workout's on-chain mint. Nil when the
    /// workout never reached the chain (stub mode, seed fixtures,
    /// or pending mint awaiting retry).
    let suiTxDigest: String?
    let walrusBlobId: String?
    let sweatMinted: Int?
}

nonisolated struct FeedItemDTO: Decodable, Hashable, Identifiable {
    let id: String
    let athlete: AthleteDTO
    let workout: WorkoutDTO
    let title: String
    let caption: String?
    let mapPreviewSeed: Int
    let kudosCount: Int
    let commentCount: Int
    let tippedSweat: Int
    let isDemo: Bool
    let createdAt: TimeInterval
}
nonisolated struct FeedEnvelope: Decodable {
    let items: [FeedItemDTO]
    /// Opaque composite cursor `"<key>:<id>"`. Pass back as-is to
    /// fetchFeedPage(before:) for the next page. `nil` = end of feed.
    let nextBefore: String?
}

nonisolated struct ClubDTO: Decodable, Hashable, Identifiable {
    let id: String
    let handle: String
    let name: String
    let tagline: String?
    let description: String?
    let heroTone: String
    let memberCount: Int
    let sweatTreasury: Int
    let weeklyKm: Double
    let isVerifiedBrand: Bool
    let tags: [String]
    let isDemo: Bool
}
nonisolated struct ClubsEnvelope: Decodable { let clubs: [ClubDTO] }

nonisolated struct ChallengeDTO: Decodable, Hashable, Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let icon: String?
    let tone: String
    let goalType: String
    let goalValue: Double
    let stakeSweat: Int
    let prizePoolSweat: Int
    let participants: Int
    let startsAt: TimeInterval
    let endsAt: TimeInterval
    let isDemo: Bool
}
nonisolated struct ChallengesEnvelope: Decodable { let challenges: [ChallengeDTO] }

nonisolated struct SegmentDTO: Decodable, Hashable, Identifiable {
    let id: String
    let name: String
    let location: String?
    let distanceMeters: Double
    let elevationGainMeters: Double
    let surface: String
    let komAthleteId: String?
    let komTimeSeconds: Int?
    let isDemo: Bool
}
nonisolated struct SegmentsEnvelope: Decodable { let segments: [SegmentDTO] }

nonisolated struct TrophyDTO: Decodable, Hashable, Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let icon: String
    let category: String
    let rarity: String
    let gradientTones: [String]
    let isLocked: Bool
    let progress: Double
    let earnedAt: TimeInterval?
    let showcaseIndex: Int?
    let isDemo: Bool
}
nonisolated struct TrophiesEnvelope: Decodable { let trophies: [TrophyDTO] }

nonisolated struct ShoeDTO: Decodable, Hashable, Identifiable {
    let id: String
    let athleteId: String
    let brand: String
    let model: String
    let nickname: String?
    let tone: String
    let milesUsed: Double
    let milesTotal: Double
    let retired: Bool
    let startedAt: TimeInterval
    let isDemo: Bool
}
nonisolated struct ShoesEnvelope: Decodable { let shoes: [ShoeDTO] }

nonisolated struct PRDTO: Decodable, Hashable, Identifiable {
    var id: String { label }
    let label: String
    let distanceMeters: Double
    let bestTimeSeconds: Int?
    let achievedAt: TimeInterval?
    let isDemo: Bool
}
nonisolated struct PRsEnvelope: Decodable { let prs: [PRDTO] }

nonisolated struct SweatEnvelope: Decodable {
    let sweat: SweatPayload
    let streak: StreakPayload?
    struct SweatPayload: Decodable { let total: Int; let weekly: Int }
    struct StreakPayload: Decodable {
        let currentDays: Int
        let longestDays: Int
        let weeklyStreakWeeks: Int
        let stakedSweat: Int
        let multiplier: Double
    }
}

nonisolated struct HealthResponse: Decodable { let ok: Bool; let ts: Double; let demoSeeded: Bool }

nonisolated struct WalletChallengeResponse: Decodable {
    let challengeId: String
    let nonce: String
    let ttlSeconds: Int
}

nonisolated struct WalletVerifyRequest: Encodable {
    let challengeId: String
    let address: String
    let signature: String
}

nonisolated struct WhoamiResponse: Decodable {
    let authenticated: Bool
    let enokiConfigured: Bool
    let userId: String?
    let suiAddress: String?
    /// "sui_valid" (66-char address from real Enoki) or "mock_truncated" (pre-Enoki fallback)
    let addressShape: String?
    let handle: String?
    let displayName: String?
    let suinsName: String?
    let suinsPresentOnThisNetwork: Bool?
    let provider: String?
    let firstSeenAt: Double?
}

nonisolated struct SuiStatusResponse: Decodable {
    let network: String
    let configured: Bool
    let packageId: String?
    let rewardsEngineId: String?
    let operatorAddress: String?
    let walrusPublisher: String
    let walrusAggregator: String
    let epoch: String?
    let indexerCursor: String?
    let explorerUrl: String
}

nonisolated struct SweatBalanceResponse: Decodable {
    let address: String
    let raw: String
    let display: String
}

nonisolated struct WorkoutOnChainResponse: Decodable {
    let workoutId: String
    let verified: Bool
    let walrusBlobId: String?
    let walrusUrl: String?
    let txDigest: String?
    let txExplorerUrl: String?
    let sweatMinted: Int
}

nonisolated struct IdEnvelope: Decodable { let id: String }

nonisolated struct AvatarUploadResponse: Decodable {
    let url: String
    let r2Key: String
}

nonisolated struct EmptyBody: Encodable {}
nonisolated struct EmptyResponse: Decodable {}

// MARK: - Request bodies

nonisolated struct AuthExchangeRequest: Encodable {
    let provider: String
    let idToken: String
    let displayName: String?
}
nonisolated struct AuthExchangeResponse: Decodable {
    let sessionJwt: String
    let userId: String?           // Server-assigned stable UUID
    let suiAddress: String        // On-chain identity
    let displayName: String
    let handle: String?
    let suinsName: String?
    let verified: Bool?
}

nonisolated struct AthletePatch: Encodable {
    var displayName: String?
    var handle: String?
    var bio: String?
    var location: String?
    var avatarTone: String?
    var bannerTone: String?
    var photoR2Key: String?
    /// Unix seconds; HealthKit age gate (13+).
    var dob: Int?
    // Extended profile fields. Same trim-empty-to-null encoding as bio/location.
    var pronouns: String?
    var websiteUrl: String?
    /// R2 key from POST /v1/media/avatar. When set the server associates
    /// the R2 object with this profile and returns the resolved photoURL.
    var avatarR2Key: String?

    init(
        displayName: String? = nil,
        handle: String? = nil,
        bio: String? = nil,
        location: String? = nil,
        avatarTone: String? = nil,
        bannerTone: String? = nil,
        photoR2Key: String? = nil,
        dob: Int? = nil,
        pronouns: String? = nil,
        websiteUrl: String? = nil,
        avatarR2Key: String? = nil
    ) {
        self.displayName = displayName
        self.handle = handle
        self.bio = bio
        self.location = location
        self.avatarTone = avatarTone
        self.bannerTone = bannerTone
        self.photoR2Key = photoR2Key
        self.dob = dob
        self.pronouns = pronouns
        self.websiteUrl = websiteUrl
        self.avatarR2Key = avatarR2Key
    }

    private enum CodingKeys: String, CodingKey {
        case displayName, handle, bio, location, avatarTone, bannerTone,
             photoR2Key, dob, pronouns, websiteUrl, avatarR2Key
    }

    /// Custom encode so that user-clearable text fields (bio, pronouns,
    /// location, websiteUrl) encode as explicit JSON `null` when the
    /// trimmed value is empty. The server treats `null` as "clear this
    /// field" and a non-null value as "set to this". Fields not provided
    /// at all (nil) remain unencoded, so other patches don't clobber
    /// untouched columns.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)

        // Clearable free-text fields: empty-string → null, set value → value.
        func encodeClearable(_ value: String?, forKey key: CodingKeys) throws {
            guard let value else { return }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                try c.encodeNil(forKey: key)
            } else {
                try c.encode(trimmed, forKey: key)
            }
        }

        // Required-but-non-clearable fields: only encode when supplied.
        // An empty displayName or handle is a validation error, not a clear.
        if let displayName { try c.encode(displayName, forKey: .displayName) }
        if let handle { try c.encode(handle, forKey: .handle) }
        try encodeClearable(bio, forKey: .bio)
        try encodeClearable(location, forKey: .location)
        if let avatarTone { try c.encode(avatarTone, forKey: .avatarTone) }
        if let bannerTone { try c.encode(bannerTone, forKey: .bannerTone) }
        if let photoR2Key { try c.encode(photoR2Key, forKey: .photoR2Key) }
        if let dob { try c.encode(dob, forKey: .dob) }
        try encodeClearable(pronouns, forKey: .pronouns)
        try encodeClearable(websiteUrl, forKey: .websiteUrl)
        if let avatarR2Key { try c.encode(avatarR2Key, forKey: .avatarR2Key) }
    }
}

nonisolated struct ReportRequest: Encodable {
    let feedItemId: String?
    let athleteId: String?
    let reason: String
}

nonisolated struct CreateClubRequest: Encodable {
    let name: String
    let handle: String
    let tagline: String?
    let description: String?
    let heroTone: String?
    let tags: [String]?
}

nonisolated struct AddShoeRequest: Encodable {
    let brand: String
    let model: String
    let nickname: String?
    let tone: String
    let milesTotal: Double
}

nonisolated struct SubmitWorkoutRequest: Encodable {
    let type: String
    let startDate: TimeInterval
    let durationSeconds: TimeInterval
    let distanceMeters: Double?
    let energyKcal: Double?
    let avgHeartRate: Double?
    let paceSecondsPerKm: Double?
    let points: Int
    let title: String
    let caption: String?
}

nonisolated struct SubmitWorkoutResponse: Decodable {
    let workoutId: String
    let feedItemId: String
    /// Post-formula Sweat that landed in the user's wallet on Sui. The
    /// number to animate in the success card. Matches the on-chain
    /// `WorkoutScored.final_reward` event in display units.
    let pointsMinted: Int
    let txDigest: String
    /// Walrus blob id of the canonical workout JSON. Nil when the
    /// pipeline ran in stub mode or Walrus upload failed.
    let walrusBlobId: String?
    /// Server-side attestation pipeline result. `pipeline` is one of
    /// "executed", "stubbed", "sui_not_configured", "walrus_upload_failed",
    /// or "sui_failed:<reason>". Surfaced in the upload-results UI so
    /// users (and us) see why a chain step failed instead of a vague
    /// "verification pending."
    let attestation: AttestationStatus?
}

nonisolated struct AttestationStatus: Decodable {
    let status: String
    let pipeline: String
}

// MARK: - Rewards DTOs

nonisolated struct RewardCatalogItemDTO: Decodable, Hashable, Identifiable {
    let id: String
    let sku: String
    let title: String
    let subtitle: String?
    let description: String?
    let imageUrl: String?
    let costPoints: Int
    let stockRemaining: Int?
}
nonisolated struct RewardsCatalogEnvelope: Decodable { let items: [RewardCatalogItemDTO] }

nonisolated struct RedemptionResponse: Decodable {
    let redemptionId: String
    let code: String
    let costPoints: Int
}

nonisolated struct SampleRedemptionResponse: Decodable, Identifiable {
    let redemptionId: String
    let costPoints: Int
    let suiAmountMist: String
    let suiAmountDisplay: String
    let txDigest: String
    let txExplorerUrl: String
    let walletExplorerUrl: String
    let message: String
    var id: String { redemptionId }
}

nonisolated struct RedemptionHistoryItemDTO: Decodable, Hashable, Identifiable {
    let id: String
    let code: String
    let costPoints: Int
    let redeemedAt: TimeInterval
    let title: String
    let sku: String
    let imageUrl: String?
}
nonisolated struct RewardsHistoryEnvelope: Decodable { let items: [RedemptionHistoryItemDTO] }
