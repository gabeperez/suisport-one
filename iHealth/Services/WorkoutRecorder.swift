import Foundation
import CoreLocation
import HealthKit
import Observation

/// Live workout recorder.
///
/// Uses the iOS 26 `HKWorkoutSession` + `HKLiveWorkoutBuilder` stack (available
/// on iPhone for the first time as of iOS 26 / WWDC25). GPS comes from the
/// modern `CLLocationUpdate.liveUpdates(.fitness)` async sequence.
///
/// This file sketches the full shape so wiring the Record tab is a fill-in job.
@Observable
@MainActor
final class WorkoutRecorder {
    enum State: Equatable { case idle, preparing, running, paused, saving, finished }

    private(set) var state: State = .idle
    private(set) var elapsed: TimeInterval = 0
    private(set) var distanceMeters: Double = 0
    private(set) var currentPaceSecondsPerKm: Double?
    private(set) var heartRate: Double?

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var routeBuilder: HKWorkoutRouteBuilder?
    private var locationTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var startedAt: Date?

    func start(type: WorkoutType) async throws {
        state = .preparing
        let config = HKWorkoutConfiguration()
        config.activityType = Self.activityType(for: type)
        config.locationType = Self.locationType(for: type)

        let session = try HKWorkoutSession(healthStore: store, configuration: config)
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
        self.session = session
        self.builder = builder
        self.routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: nil)

        let start = Date()
        session.startActivity(with: start)
        try await builder.beginCollection(at: start)
        self.startedAt = start
        state = .running

        startTimer()
        startLocationStream()
    }

    func pause() {
        guard state == .running else { return }
        session?.pause()
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        session?.resume()
        state = .running
    }

    func finish() async throws -> Workout? {
        guard let session, let builder else { return nil }
        state = .saving
        locationTask?.cancel()
        tickTask?.cancel()

        let end = Date()
        session.end()
        try await builder.endCollection(at: end)
        let hk = try await builder.finishWorkout()

        // Finalize route only if we captured something AND a real HKWorkout exists.
        if let route = routeBuilder, let hk {
            _ = try? await route.finishRoute(with: hk, metadata: nil)
        }

        reset()
        state = .finished
        guard let hk else { return nil }
        return HealthKitService.workout(from: hk)
    }

    // MARK: - Internals

    private func reset() {
        session = nil
        builder = nil
        routeBuilder = nil
        locationTask = nil
        tickTask = nil
    }

    private func startTimer() {
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000)
                await MainActor.run {
                    guard let self, let s = self.startedAt, self.state == .running else { return }
                    self.elapsed = Date().timeIntervalSince(s)
                }
            }
        }
    }

    private func startLocationStream() {
        locationTask = Task { [weak self] in
            do {
                let updates = CLLocationUpdate.liveUpdates(.fitness)
                var last: CLLocation?
                for try await update in updates {
                    if Task.isCancelled { break }
                    guard let loc = update.location, loc.horizontalAccuracy >= 0,
                          loc.horizontalAccuracy < 20 else { continue }
                    await MainActor.run {
                        guard let self, self.state == .running else { return }
                        if let last { self.distanceMeters += loc.distance(from: last) }
                    }
                    last = loc
                    _ = try? await self?.routeBuilder?.insertRouteData([loc])
                }
            } catch {
                // Quietly stop; the builder still captures samples via HK.
            }
        }
    }

    private static func activityType(for type: WorkoutType) -> HKWorkoutActivityType {
        switch type {
        case .run: return .running
        case .walk: return .walking
        case .ride: return .cycling
        case .swim: return .swimming
        case .hike: return .hiking
        case .yoga: return .yoga
        case .hiit: return .highIntensityIntervalTraining
        case .lift: return .traditionalStrengthTraining
        // Fight-camp types — Apple HealthKit has dedicated cases for
        // every one. Mapping is the inverse of HealthKitService.mapType
        // so a session recorded here round-trips correctly when the
        // backfill picks it up later.
        case .striking:     return .boxing
        case .grappling:    return .wrestling
        case .mma:          return .martialArts
        case .conditioning: return .mixedCardio
        case .recovery:     return .flexibility
        case .other:        return .other
        }
    }

    private static func locationType(for type: WorkoutType) -> HKWorkoutSessionLocationType {
        switch type {
        case .run, .walk, .ride, .hike: return .outdoor
        default: return .indoor
        }
    }
}
