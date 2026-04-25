import SwiftUI

/// Live recording screen — fills the whole sheet while a workout is
/// underway. Shows a giant running duration, four metric tiles, and a
/// start/pause/stop control ring. Drives `WorkoutRecorder` for the
/// HealthKit side; on finish submits a `SubmitWorkoutRequest` to the
/// server so the mint pipeline fires.
struct LiveRecorderView: View {
    let type: WorkoutType
    @Environment(AppState.self) private var app
    @Environment(SocialDataService.self) private var social
    @Environment(\.dismiss) private var dismiss

    @State private var recorder = WorkoutRecorder()
    @State private var showEndConfirm = false
    @State private var submitError: String?
    @State private var startError: String?
    @State private var isSubmitting = false
    /// The workout + prepared request held over for Retry. Kept around
    /// while submit fails so the user can re-attempt without losing the
    /// captured session, and cleared on success or Discard.
    @State private var pendingSubmit: PendingSubmit?

    private struct PendingSubmit {
        let workout: Workout
        let request: SubmitWorkoutRequest
    }

    var body: some View {
        VStack(spacing: Theme.Space.lg) {
            header
            timer
            metrics
            Spacer()
            controls
        }
        .padding(Theme.Space.lg)
        .background(Theme.Color.bg.ignoresSafeArea())
        .task { await startIfNeeded() }
        .alert("End this \(type.title.lowercased())?", isPresented: $showEndConfirm) {
            Button("Keep going", role: .cancel) {}
            Button("End + save", role: .destructive) {
                Task { await finish() }
            }
        } message: {
            Text("We'll mint the proof + points now.")
        }
        .alert("Couldn't start recording", isPresented: Binding(
            get: { startError != nil },
            set: { if !$0 { startError = nil } }
        )) {
            Button("OK", role: .cancel) { dismiss() }
        } message: {
            Text(startError ?? "")
        }
        .alert("Couldn't save workout", isPresented: Binding(
            get: { submitError != nil },
            set: { if !$0 { submitError = nil } }
        )) {
            Button("Retry") {
                Task { await retrySubmit() }
            }
            Button("Discard", role: .destructive) {
                pendingSubmit = nil
                submitError = nil
                dismiss()
            }
            Button("Cancel", role: .cancel) {
                // Keep pendingSubmit so the user can retry later from
                // the workout-in-limbo UI (future).
                submitError = nil
            }
        } message: {
            Text(submitError ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Theme.Color.accent.opacity(0.2))
                        .frame(width: 36, height: 36)
                    Image(systemName: type.icon)
                        .foregroundStyle(Theme.Color.accentDeep)
                        .font(.system(size: 16, weight: .bold))
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(type.title)
                        .font(.titleM).foregroundStyle(Theme.Color.ink)
                    Text(recorderStateLabel)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(stateTint)
                }
            }
            Spacer()
            if recorder.state == .idle || recorder.state == .preparing {
                Button {
                    Haptics.tap(); dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.Color.inkSoft)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Theme.Color.bgElevated))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var recorderStateLabel: String {
        switch recorder.state {
        case .idle: return "Preparing…"
        case .preparing: return "Warming up…"
        case .running: return "Recording"
        case .paused: return "Paused"
        case .saving: return "Saving…"
        case .finished: return "Done"
        }
    }

    private var stateTint: Color {
        switch recorder.state {
        case .running: return Theme.Color.accentDeep
        case .paused: return Theme.Color.gold
        case .saving, .finished: return Theme.Color.accentDeep
        default: return Theme.Color.inkSoft
        }
    }

    // MARK: - Timer

    private var timer: some View {
        VStack(spacing: 6) {
            Text(Self.format(recorder.elapsed))
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.Color.ink)
                .contentTransition(.numericText())
            Text("DURATION")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(Theme.Color.inkFaint)
        }
        .padding(.top, Theme.Space.md)
    }

    // MARK: - Metrics grid

    private var metrics: some View {
        let cols = [GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)]
        return LazyVGrid(columns: cols, spacing: 12) {
            metricTile(label: "Distance",
                       value: distanceDisplay,
                       icon: "arrow.right.circle.fill",
                       tint: Theme.Color.accent)
            metricTile(label: "Pace",
                       value: paceDisplay,
                       icon: "speedometer",
                       tint: Theme.Color.sky)
            metricTile(label: "Heart rate",
                       value: hrDisplay,
                       icon: "heart.fill",
                       tint: Theme.Color.hot)
            metricTile(label: "Calories",
                       value: "—",
                       icon: "flame.fill",
                       tint: Theme.Color.gold)
        }
    }

    private func metricTile(label: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tint)
                Text(label)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(Theme.Color.inkFaint)
                Spacer()
            }
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.Color.ink)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.lg)
            .fill(Theme.Color.bgElevated))
    }

    private var distanceDisplay: String {
        let km = recorder.distanceMeters / 1000
        return km < 0.01 ? "0.00 km" : String(format: "%.2f km", km)
    }

    private var paceDisplay: String {
        guard let p = recorder.currentPaceSecondsPerKm, p > 0, p.isFinite else {
            // Derive from current data as fallback.
            if recorder.distanceMeters > 50 && recorder.elapsed > 10 {
                let secPerKm = recorder.elapsed / (recorder.distanceMeters / 1000)
                return paceString(secPerKm)
            }
            return "—"
        }
        return paceString(p)
    }

    private var hrDisplay: String {
        guard let hr = recorder.heartRate else { return "—" }
        return "\(Int(hr)) bpm"
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 18) {
            switch recorder.state {
            case .running:
                secondaryButton("Pause", icon: "pause.fill") {
                    Haptics.tap(); recorder.pause()
                }
                primaryButton("End", icon: "stop.fill",
                              tint: Theme.Color.hot) {
                    Haptics.thud()
                    showEndConfirm = true
                }
            case .paused:
                secondaryButton("Resume", icon: "play.fill") {
                    Haptics.tap(); recorder.resume()
                }
                primaryButton("End", icon: "stop.fill",
                              tint: Theme.Color.hot) {
                    Haptics.thud(); showEndConfirm = true
                }
            case .preparing, .idle:
                ProgressView().frame(maxWidth: .infinity).frame(height: 60)
            case .saving:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Minting your proof…")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.Color.inkSoft)
                }
                .frame(maxWidth: .infinity).frame(height: 60)
            case .finished:
                primaryButton("Done", icon: "checkmark", tint: Theme.Color.accentDeep) {
                    dismiss()
                }
            }
        }
    }

    private func primaryButton(_ title: String, icon: String, tint: Color,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 16, weight: .bold))
                Text(title).font(.system(size: 17, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(Capsule().fill(tint))
            .shadow(color: tint.opacity(0.4), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
    }

    private func secondaryButton(_ title: String, icon: String,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 16, weight: .bold))
                Text(title).font(.system(size: 17, weight: .bold, design: .rounded))
            }
            .foregroundStyle(Theme.Color.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(Capsule().fill(Theme.Color.bgElevated))
            .overlay(Capsule().strokeBorder(Theme.Color.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Lifecycle

    private func startIfNeeded() async {
        guard recorder.state == .idle else { return }
        do {
            try await recorder.start(type: type)
        } catch {
            startError = error.localizedDescription
        }
    }

    @MainActor
    private func finish() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            guard let workout = try await recorder.finish() else {
                submitError = "We didn't capture any movement for this session."
                return
            }
            let req = SubmitWorkoutRequest(
                type: workout.type.rawValue,
                startDate: workout.startDate.timeIntervalSince1970,
                durationSeconds: workout.duration,
                distanceMeters: workout.distanceMeters,
                energyKcal: workout.energyKcal,
                avgHeartRate: workout.avgHeartRate,
                paceSecondsPerKm: workout.paceSecondsPerKm,
                points: workout.points,
                title: defaultTitle(for: workout),
                caption: nil
            )
            let pending = PendingSubmit(workout: workout, request: req)
            pendingSubmit = pending
            await submit(pending)
        } catch {
            submitError = error.localizedDescription
        }
    }

    /// Re-submit the last pending payload. Called from the error alert
    /// Retry button; a no-op if we already lost the payload (Discard).
    @MainActor
    private func retrySubmit() async {
        guard let pending = pendingSubmit else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        await submit(pending)
    }

    @MainActor
    private func submit(_ pending: PendingSubmit) async {
        // Skip the network call if this exact workout (by HealthKit
        // UUID) is already minted on chain. The server's
        // canonical_hash check would reject it anyway with a 422 —
        // catching it here means the UI flips straight to "✓ on
        // chain" instead of flashing a spinner before an error.
        if app.isAlreadyOnChain(pending.workout) {
            pendingSubmit = nil
            Haptics.success()
            return
        }
        do {
            _ = try await APIClient.shared.submitWorkout(pending.request)
            pendingSubmit = nil
            // Mark the cached workout verified so future relaunches
            // recognize it without another submit attempt.
            if let idx = app.workouts.firstIndex(where: { $0.id == pending.workout.id }) {
                app.workouts[idx].verified = true
            }
            // Refresh the feed so the new workout shows up immediately.
            await social.refresh()
            Haptics.success()
        } catch {
            submitError = error.localizedDescription
            Haptics.warn()
        }
    }

    // MARK: - Helpers

    private func paceString(_ secPerKm: Double) -> String {
        let m = Int(secPerKm) / 60
        let s = Int(secPerKm) % 60
        return String(format: "%d:%02d /km", m, s)
    }

    private static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    private func defaultTitle(for w: Workout) -> String {
        let hour = Calendar.current.component(.hour, from: w.startDate)
        let when: String
        switch hour {
        case 5..<10: when = "Morning"
        case 10..<14: when = "Midday"
        case 14..<18: when = "Afternoon"
        case 18..<22: when = "Evening"
        default: when = "Late-night"
        }
        return "\(when) \(w.type.title.lowercased())"
    }
}
