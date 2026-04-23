import Foundation

/// A benchmark-distance PR. Computed from the athlete's historical workouts.
/// When achieved, the corresponding Sui object (and soulbound trophy) becomes
/// provable — impossible to fake.
struct PersonalRecord: Identifiable, Hashable {
    var id: String { label }
    var label: String                       // "5K", "10K", "Half", "Full"
    var distanceMeters: Double
    var bestTimeSeconds: Int?               // nil if not yet achieved
    var achievedAt: Date?

    static let benchmarks: [PersonalRecord] = [
        .init(label: "5K", distanceMeters: 5_000, bestTimeSeconds: nil, achievedAt: nil),
        .init(label: "10K", distanceMeters: 10_000, bestTimeSeconds: nil, achievedAt: nil),
        .init(label: "Half", distanceMeters: 21_097, bestTimeSeconds: nil, achievedAt: nil),
        .init(label: "Full", distanceMeters: 42_195, bestTimeSeconds: nil, achievedAt: nil)
    ]

    var formattedTime: String {
        guard let t = bestTimeSeconds else { return "—" }
        let h = t / 3600
        let m = (t % 3600) / 60
        let s = t % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}

/// Derives PRs from a workout list. We consider a workout at benchmark if
/// its distance is >= the benchmark distance; best time is the workout
/// duration for the fastest such workout. This is coarse — a proper
/// implementation parses splits to find the fastest 5K inside a longer
/// run — but it's enough for the Profile UI.
enum PRCalculator {
    static func pr(label: String, distanceM: Double, workouts: [Workout]) -> PersonalRecord {
        let qualifying = workouts.filter {
            $0.type == .run && ($0.distanceMeters ?? 0) >= distanceM
        }
        let fastest = qualifying.min { a, b in
            let aRate = a.duration / (a.distanceMeters ?? distanceM)
            let bRate = b.duration / (b.distanceMeters ?? distanceM)
            return aRate < bRate
        }
        guard let w = fastest else {
            return PersonalRecord(label: label, distanceMeters: distanceM,
                                  bestTimeSeconds: nil, achievedAt: nil)
        }
        let rate = w.duration / (w.distanceMeters ?? distanceM)
        let time = Int(rate * distanceM)
        return PersonalRecord(label: label, distanceMeters: distanceM,
                              bestTimeSeconds: time, achievedAt: w.startDate)
    }

    static func all(from workouts: [Workout]) -> [PersonalRecord] {
        PersonalRecord.benchmarks.map {
            pr(label: $0.label, distanceM: $0.distanceMeters, workouts: workouts)
        }
    }
}
