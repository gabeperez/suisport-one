import Foundation
import HealthKit

/// Wraps HealthKit for the two operations we actually need:
///   1. Request the minimum-useful permission set.
///   2. Load historical workouts to surface the "we found N workouts" moment.
///
/// Live recording is handled by `WorkoutRecorder`.
@MainActor
final class HealthKitService {
    static let shared = HealthKitService()

    let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // MARK: - Authorization

    private var shareTypes: Set<HKSampleType> {
        var s: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
            HKSeriesType.workoutType()
        ]
        if let hr = HKQuantityType.quantityType(forIdentifier: .heartRate) { s.insert(hr) }
        if let kcal = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) { s.insert(kcal) }
        if let drun = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) { s.insert(drun) }
        if let dcycle = HKQuantityType.quantityType(forIdentifier: .distanceCycling) { s.insert(dcycle) }
        return s
    }

    private var readTypes: Set<HKObjectType> {
        var s: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute()
        ]
        if let hr = HKQuantityType.quantityType(forIdentifier: .heartRate) { s.insert(hr) }
        if let kcal = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) { s.insert(kcal) }
        if let drun = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) { s.insert(drun) }
        if let dcycle = HKQuantityType.quantityType(forIdentifier: .distanceCycling) { s.insert(dcycle) }
        if let step = HKQuantityType.quantityType(forIdentifier: .stepCount) { s.insert(step) }
        return s
    }

    /// Request HealthKit authorization. Throws if not available.
    func requestAuthorization() async throws {
        guard isAvailable else { throw HKError(.errorHealthDataUnavailable) }
        try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
    }

    /// Inspectable only for WRITE types. For reads HealthKit does not reveal status.
    func writeAuthorized() -> Bool {
        store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
    }

    // MARK: - Historical workouts

    struct BackfillProgress {
        var found: Int
        var isComplete: Bool
    }

    /// Load all workouts since `from`. Converts them to our `Workout` model.
    /// Streams progress back via `onProgress` so the "we found N workouts" screen
    /// can animate the counter up.
    func loadHistoricalWorkouts(
        since from: Date = Calendar.current.date(byAdding: .year, value: -1, to: .now) ?? .now,
        onProgress: @escaping (Int) -> Void
    ) async throws -> [Workout] {
        guard isAvailable else { return [] }

        let predicate = HKQuery.predicateForSamples(withStart: from, end: .now, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let samples: [HKSample] = try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error = error { cont.resume(throwing: error) }
                else { cont.resume(returning: samples ?? []) }
            }
            store.execute(q)
        }

        var result: [Workout] = []
        result.reserveCapacity(samples.count)

        for (i, sample) in samples.enumerated() {
            guard let hk = sample as? HKWorkout else { continue }
            result.append(Self.workout(from: hk))
            if i % 3 == 0 {
                let snapshot = result.count
                await MainActor.run { onProgress(snapshot) }
                // Visually pace the counter a little for the "backfill celebration" screen
                try? await Task.sleep(nanoseconds: 12_000_000)
            }
        }
        await MainActor.run { onProgress(result.count) }
        return result
    }

    // MARK: - Conversion

    static func workout(from hk: HKWorkout) -> Workout {
        let type = mapType(hk.workoutActivityType)
        let source = hk.sourceRevision.source.bundleIdentifier
        let userEntered = (hk.metadata?[HKMetadataKeyWasUserEntered] as? Bool) ?? false

        // Duration: prefer active duration over wall-clock.
        let duration = hk.duration

        // Prefer activity-specific statistics when available (HealthKit-native).
        // `totalDistance` is still the canonical distance accessor on HKWorkout.
        // `totalEnergyBurned` was deprecated in iOS 18 in favor of
        // `statistics(for:)` on the associated type — we use the new API here.
        let distance = hk.totalDistance?.doubleValue(for: .meter())
        let energyType = HKQuantityType(.activeEnergyBurned)
        let energy = hk.statistics(for: energyType)?
            .sumQuantity()?
            .doubleValue(for: .kilocalorie())

        var w = Workout(
            id: hk.uuid,
            type: type,
            startDate: hk.startDate,
            endDate: hk.endDate,
            duration: duration,
            distanceMeters: distance,
            energyKcal: energy,
            avgHeartRate: nil,
            source: source,
            isUserEntered: userEntered,
            points: 0,
            verified: false,
            synced: false
        )
        w.points = SweatPoints.forWorkout(w)
        return w
    }

    static func mapType(_ a: HKWorkoutActivityType) -> WorkoutType {
        switch a {
        case .running: return .run
        case .walking: return .walk
        case .cycling: return .ride
        case .swimming: return .swim
        case .hiking: return .hike
        case .yoga: return .yoga
        case .highIntensityIntervalTraining: return .hiit
        case .functionalStrengthTraining, .traditionalStrengthTraining, .coreTraining: return .lift
        // Martial-arts mapping — Apple's HKWorkoutActivityType has
        // dedicated cases for boxing / kickboxing / wrestling /
        // martialArts. We collapse boxing + kickboxing into
        // "striking" because the iOS UI treats them the same way
        // (the user picked their style on profile setup; here we
        // care about whether it was a striking session).
        case .boxing, .kickboxing: return .striking
        case .wrestling: return .grappling
        case .martialArts: return .mma
        case .mixedCardio: return .conditioning
        case .flexibility, .cooldown, .preparationAndRecovery: return .recovery
        default: return .other
        }
    }
}
