import SwiftUI

/// Full-screen celebration that runs while a workout is minting on
/// chain. Replaces the old inline ProgressView spinner — gives the
/// user a beat to watch while the worker round-trip + Sui settlement
/// happen (typically 3–8s).
///
/// Choreography (Apple-Watch-ring inspired):
///   1. Backdrop fades + content scales in (entrance)
///   2. Gradient ring fills 0 → 0.85 over ~7s as the mint is in flight,
///      avatar gently pulses inside the ring, Sweat counter ticks up
///   3. On success: ring snaps to 1.0 with a spring, counter snaps to
///      target, seal stamps over the avatar, caption flips to
///      "Verified on Sui"
///   4. Holds the celebration ~1.4s, then fades out and calls
///      onComplete so the parent can dismiss + run any post-mint
///      bookkeeping
///
/// On error, fades out fast and forwards the error to the parent —
/// parent owns the error alert / 422-duplicate special-casing.
struct MintingCelebrationView: View {
    let workout: Workout
    let athlete: Athlete?
    let perform: () async throws -> SubmitWorkoutResponse
    let onComplete: (Result<SubmitWorkoutResponse, Error>) -> Void

    @State private var ringProgress: Double = 0
    @State private var displayedReward: Double = 0
    @State private var avatarPulse: Bool = false
    @State private var sealVisible: Bool = false
    @State private var caption: String = "Claiming on Sui…"
    @State private var contentScale: Double = 0.92
    @State private var contentOpacity: Double = 0
    @State private var didStart = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()
            VStack(spacing: 28) {
                avatarStack
                rewardBlock
                workoutChip
            }
            .scaleEffect(contentScale)
            .opacity(contentOpacity)
        }
        .task {
            // .task runs every time the view appears; guard so we
            // don't accidentally double-fire the mint on re-render.
            guard !didStart else { return }
            didStart = true
            await runMint()
        }
    }

    // MARK: - Avatar + ring

    private var avatarStack: some View {
        ZStack {
            // Faint background track so the user can see the full
            // path the gradient ring is traveling along.
            Circle()
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 6)
                .frame(width: 220, height: 220)
            // Active ring — fills clockwise from the top.
            Circle()
                .trim(from: 0, to: ringProgress)
                .stroke(
                    athlete?.avatarTone.gradient
                        ?? AvatarTone.sunset.gradient,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 220, height: 220)
                .shadow(
                    color: (athlete?.avatarTone.colors.0 ?? Theme.Color.accent)
                        .opacity(0.45),
                    radius: 14, y: 0
                )
            avatarBubble
                .scaleEffect(avatarPulse ? 1.04 : 1.0)
            if sealVisible {
                sealStamp
                    .transition(
                        .scale(scale: 0.5)
                            .combined(with: .opacity)
                    )
            }
        }
        .frame(width: 220, height: 220)
    }

    @ViewBuilder
    private var avatarBubble: some View {
        if let athlete {
            AthleteAvatar(athlete: athlete, size: 150, showsTierRing: false)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 2))
        } else {
            Circle()
                .fill(Theme.Color.bgElevated)
                .frame(width: 150, height: 150)
                .overlay(
                    Image(systemName: "figure.run")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                )
        }
    }

    private var sealStamp: some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: 78, height: 78)
                .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 60, weight: .bold))
                .foregroundStyle(Theme.Color.accentDeep)
        }
    }

    // MARK: - Reward block

    /// Pre-allocated width so the "Sweat" label doesn't shift as
    /// digits roll over. Sized to the target's digit count + a hair
    /// of slack so the number text always fits cleanly without the
    /// numericText transition clipping its mask against the edge.
    private var rewardDigitsWidth: CGFloat {
        let target = max(workout.points, 1)
        let digits = String(target).count
        // ~22pt per digit at the 44pt rounded-bold font + 24pt for the leading "+".
        return CGFloat(digits) * 22 + 24
    }

    private var rewardBlock: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "bolt.heart.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                // Digits live in their own fixed-width slot so the
                // numericText flipboard transition has stable bounds
                // — without this the text frame grows as digits add,
                // which makes the number look like it's "covered and
                // expanding" mid-roll.
                Text("+\(Int(displayedReward))")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(value: displayedReward))
                    .monospacedDigit()
                    .frame(minWidth: rewardDigitsWidth, alignment: .trailing)
                Text("Sweat")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
            }
            // Backdrop card keeps the number clearly visible no
            // matter what the ring/seal animation is doing behind.
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                    )
            )
            Text(caption)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.65))
                .contentTransition(.opacity)
        }
    }

    private var workoutChip: some View {
        HStack(spacing: 8) {
            Image(systemName: workout.type.icon)
                .font(.system(size: 11, weight: .bold))
            Text(workout.type.title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Capsule().fill(Color.white.opacity(0.10)))
    }

    // MARK: - Choreography

    @MainActor
    private func runMint() async {
        // Entrance
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            contentScale = 1.0
            contentOpacity = 1.0
        }
        Haptics.thud()

        // Ring + counter share the same curve so the digit ticker
        // visually "drives" the ring filling. Caps at 85% so the
        // user senses there's a "lock-in" beat coming when the
        // chain confirms (snaps to 100% in celebrate()).
        let fillCurve = Animation.easeInOut(duration: 6.5)
        let target = Double(max(0, workout.points))
        withAnimation(fillCurve) {
            ringProgress = 0.85
            displayedReward = target * 0.85
        }
        withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
            avatarPulse = true
        }

        do {
            let resp = try await perform()
            await celebrate(target: target)
            onComplete(.success(resp))
        } catch {
            // Fade the celebration out before handing the error
            // back so the parent's alert doesn't pop on top of a
            // half-faded ring.
            withAnimation(.easeIn(duration: 0.22)) {
                contentOpacity = 0
            }
            try? await Task.sleep(nanoseconds: 240_000_000)
            onComplete(.failure(error))
        }
    }

    @MainActor
    private func celebrate(target: Double) async {
        // Snap ring + counter to full with a satisfying spring.
        withAnimation(.spring(response: 0.45, dampingFraction: 0.62)) {
            ringProgress = 1.0
        }
        withAnimation(.easeOut(duration: 0.55)) {
            displayedReward = target
        }
        // Stop the breathing pulse — the moment is sharp, not soft.
        withAnimation(.easeOut(duration: 0.25)) {
            avatarPulse = false
        }
        // Slight delay so the ring close reads before the seal lands.
        try? await Task.sleep(nanoseconds: 220_000_000)
        Haptics.success()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.55)) {
            sealVisible = true
        }
        withAnimation(.easeInOut(duration: 0.3)) {
            caption = "Verified on Sui"
        }
        // Hold the celebration so the user can take it in.
        try? await Task.sleep(nanoseconds: 1_400_000_000)
        withAnimation(.easeIn(duration: 0.32)) {
            contentOpacity = 0
        }
        try? await Task.sleep(nanoseconds: 340_000_000)
    }
}

/// Convenience descriptor for presenting the celebration. Carries the
/// workout to mint plus the parent callback for the result; an
/// Identifiable wrapper makes it easy to drive `.fullScreenCover(item:)`.
struct MintingCelebrationRequest: Identifiable {
    let id = UUID()
    let workout: Workout
    let onResult: (Result<SubmitWorkoutResponse, Error>) -> Void
}
