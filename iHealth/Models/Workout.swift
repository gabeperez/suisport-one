import Foundation

struct Workout: Identifiable, Hashable, Codable {
    var id: UUID
    var type: WorkoutType
    var startDate: Date
    var endDate: Date
    var duration: TimeInterval          // active seconds, excluding pauses
    var distanceMeters: Double?
    var energyKcal: Double?
    var avgHeartRate: Double?
    var source: String                  // bundleId of recording app
    var isUserEntered: Bool
    /// Points awarded (or to-be-awarded) for this workout.
    var points: Int
    /// True once the attestation has been submitted to Sui.
    var verified: Bool
    /// True if the blob has been uploaded to Walrus.
    var synced: Bool

    var paceSecondsPerKm: Double? {
        guard let d = distanceMeters, d > 0 else { return nil }
        return duration / (d / 1000.0)
    }
}

enum WorkoutType: String, Codable, CaseIterable, Hashable {
    // Generic activity (kept so prior backfill data still decodes).
    case run, walk, ride, swim, lift, yoga, hiit, hike
    // Martial-arts focused — what an ONE Championship fighter actually
    // logs. Wire-codes 6–10 in the backend `workoutTypeCode()` mirror.
    case striking, grappling, mma, conditioning, recovery
    case other

    var title: String {
        switch self {
        case .run: return "Run"
        case .walk: return "Walk"
        case .ride: return "Ride"
        case .swim: return "Swim"
        case .lift: return "Strength"
        case .yoga: return "Yoga"
        case .hiit: return "HIIT"
        case .hike: return "Hike"
        case .striking: return "Striking"
        case .grappling: return "Grappling"
        case .mma: return "MMA"
        case .conditioning: return "Conditioning"
        case .recovery: return "Recovery"
        case .other: return "Workout"
        }
    }

    /// SF Symbol. Boxing / wrestling / martial-arts symbols ship from
    /// iOS 17. The fallback `figure.cross.training` is a safe pick for
    /// older sims.
    var icon: String {
        switch self {
        case .run: return "figure.run"
        case .walk: return "figure.walk"
        case .ride: return "figure.outdoor.cycle"
        case .swim: return "figure.pool.swim"
        case .lift: return "figure.strengthtraining.traditional"
        case .yoga: return "figure.yoga"
        case .hiit: return "bolt.heart.fill"
        case .hike: return "figure.hiking"
        case .striking: return "figure.boxing"
        case .grappling: return "figure.wrestling"
        case .mma: return "figure.martial.arts"
        case .conditioning: return "figure.cross.training"
        case .recovery: return "figure.flexibility"
        case .other: return "figure.mixed.cardio"
        }
    }

    /// True when the type is fight-camp adjacent. Used to filter the
    /// ONE-flavored UI (challenges, leaderboards) so a runner doesn't
    /// drown out the martial-arts narrative.
    var isFightCamp: Bool {
        switch self {
        case .striking, .grappling, .mma, .conditioning, .recovery:
            return true
        default:
            return false
        }
    }
}
