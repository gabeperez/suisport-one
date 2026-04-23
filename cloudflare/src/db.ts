// D1 row types + DTO mappers. The mappers shape the JSON the iOS client
// consumes — keep field names camelCase there so Swift `JSONDecoder` works.

export type AthleteRow = {
    id: string;
    handle: string;
    display_name: string;
    avatar_tone: string;
    banner_tone: string;
    verified: number;
    tier: string;
    total_workouts: number;
    followers_count: number;
    following_count: number;
    bio: string | null;
    location: string | null;
    photo_r2_key: string | null;
    is_demo: number;
};

export type WorkoutRow = {
    id: string;
    athlete_id: string;
    type: string;
    start_date: number;
    duration_seconds: number;
    distance_meters: number | null;
    energy_kcal: number | null;
    avg_heart_rate: number | null;
    pace_seconds_per_km: number | null;
    points: number;
    verified: number;
    is_demo: number;
};

export type FeedItemRow = {
    id: string;
    athlete_id: string;
    workout_id: string;
    title: string;
    caption: string | null;
    map_preview_seed: number;
    kudos_count: number;
    comment_count: number;
    tipped_sweat: number;
    is_demo: number;
    created_at: number;
};

export type ClubRow = {
    id: string;
    handle: string;
    name: string;
    tagline: string | null;
    description: string | null;
    hero_tone: string;
    member_count: number;
    sweat_treasury: number;
    weekly_km: number;
    is_verified_brand: number;
    tags: string;
    is_demo: number;
};

export type ChallengeRow = {
    id: string;
    title: string;
    subtitle: string | null;
    sponsor: string | null;
    icon: string | null;
    tone: string;
    goal_type: string;
    goal_value: number;
    stake_sweat: number;
    prize_pool_sweat: number;
    participants: number;
    starts_at: number;
    ends_at: number;
    is_demo: number;
};

export type SegmentRow = {
    id: string;
    name: string;
    location: string | null;
    distance_meters: number;
    elevation_gain_meters: number;
    surface: string;
    kom_athlete_id: string | null;
    kom_time_seconds: number | null;
    is_demo: number;
};

export type TrophyRow = {
    id: string;
    title: string;
    subtitle: string | null;
    icon: string;
    category: string;
    rarity: string;
    gradient_tones: string;
    is_demo: number;
};

export type ShoeRow = {
    id: string;
    athlete_id: string;
    brand: string;
    model: string;
    nickname: string | null;
    tone: string;
    miles_used: number;
    miles_total: number;
    retired: number;
    started_at: number;
    is_demo: number;
};

export type PRRow = {
    athlete_id: string;
    label: string;
    distance_meters: number;
    best_time_seconds: number | null;
    achieved_at: number | null;
    is_demo: number;
};

// ---------- DTO mappers (snake_case DB rows → camelCase JSON for Swift) ----------

export function athleteDTO(r: AthleteRow) {
    return {
        id: r.id,
        handle: r.handle,
        displayName: r.display_name,
        avatarTone: r.avatar_tone,
        bannerTone: r.banner_tone,
        verified: r.verified === 1,
        tier: r.tier,
        totalWorkouts: r.total_workouts,
        followers: r.followers_count,
        following: r.following_count,
        bio: r.bio,
        location: r.location,
        photoURL: r.photo_r2_key ? `/media/${r.photo_r2_key}` : null,
        isDemo: r.is_demo === 1,
    };
}

export function workoutDTO(r: WorkoutRow) {
    return {
        id: r.id,
        athleteId: r.athlete_id,
        type: r.type,
        startDate: r.start_date,
        durationSeconds: r.duration_seconds,
        distanceMeters: r.distance_meters,
        energyKcal: r.energy_kcal,
        avgHeartRate: r.avg_heart_rate,
        paceSecondsPerKm: r.pace_seconds_per_km,
        points: r.points,
        verified: r.verified === 1,
        isDemo: r.is_demo === 1,
    };
}

export function feedItemDTO(r: FeedItemRow, athlete: AthleteRow, workout: WorkoutRow) {
    return {
        id: r.id,
        athlete: athleteDTO(athlete),
        workout: workoutDTO(workout),
        title: r.title,
        caption: r.caption,
        mapPreviewSeed: r.map_preview_seed,
        kudosCount: r.kudos_count,
        commentCount: r.comment_count,
        tippedSweat: r.tipped_sweat,
        isDemo: r.is_demo === 1,
        createdAt: r.created_at,
    };
}

export function clubDTO(r: ClubRow) {
    let tags: string[] = [];
    try { tags = JSON.parse(r.tags); } catch { /* noop */ }
    return {
        id: r.id,
        handle: r.handle,
        name: r.name,
        tagline: r.tagline,
        description: r.description,
        heroTone: r.hero_tone,
        memberCount: r.member_count,
        sweatTreasury: r.sweat_treasury,
        weeklyKm: r.weekly_km,
        isVerifiedBrand: r.is_verified_brand === 1,
        tags,
        isDemo: r.is_demo === 1,
    };
}

export function challengeDTO(r: ChallengeRow) {
    let sponsor: { name: string } | null = null;
    if (r.sponsor) {
        try { sponsor = JSON.parse(r.sponsor); } catch { /* noop */ }
    }
    return {
        id: r.id,
        title: r.title,
        subtitle: r.subtitle,
        sponsor,
        icon: r.icon,
        tone: r.tone,
        goalType: r.goal_type,
        goalValue: r.goal_value,
        stakeSweat: r.stake_sweat,
        prizePoolSweat: r.prize_pool_sweat,
        participants: r.participants,
        startsAt: r.starts_at,
        endsAt: r.ends_at,
        isDemo: r.is_demo === 1,
    };
}

export function segmentDTO(r: SegmentRow) {
    return {
        id: r.id,
        name: r.name,
        location: r.location,
        distanceMeters: r.distance_meters,
        elevationGainMeters: r.elevation_gain_meters,
        surface: r.surface,
        komAthleteId: r.kom_athlete_id,
        komTimeSeconds: r.kom_time_seconds,
        isDemo: r.is_demo === 1,
    };
}

export function trophyDTO(r: TrophyRow, unlock?: { progress: number; earned_at: number | null; showcase_index: number | null }) {
    let gradientTones: string[] = [];
    try { gradientTones = JSON.parse(r.gradient_tones); } catch { /* noop */ }
    return {
        id: r.id,
        title: r.title,
        subtitle: r.subtitle,
        icon: r.icon,
        category: r.category,
        rarity: r.rarity,
        gradientTones,
        isLocked: unlock ? unlock.earned_at == null : true,
        progress: unlock?.progress ?? 0,
        earnedAt: unlock?.earned_at ?? null,
        showcaseIndex: unlock?.showcase_index ?? null,
        isDemo: r.is_demo === 1,
    };
}

export function shoeDTO(r: ShoeRow) {
    return {
        id: r.id,
        athleteId: r.athlete_id,
        brand: r.brand,
        model: r.model,
        nickname: r.nickname,
        tone: r.tone,
        milesUsed: r.miles_used,
        milesTotal: r.miles_total,
        retired: r.retired === 1,
        startedAt: r.started_at,
        isDemo: r.is_demo === 1,
    };
}

export function prDTO(r: PRRow) {
    return {
        label: r.label,
        distanceMeters: r.distance_meters,
        bestTimeSeconds: r.best_time_seconds,
        achievedAt: r.achieved_at,
        isDemo: r.is_demo === 1,
    };
}
