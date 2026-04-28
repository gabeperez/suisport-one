import SwiftUI

/// Full view of a fighter's training camp — sequenced sessions with
/// per-user progress. Sessions before the current one show as
/// "Completed" with a checkmark; the current session has the live
/// "Start session" CTA; everything past the current session is locked
/// behind a soft padlock so the user can see what's coming but can't
/// skip ahead.
///
/// Surfaced from three places:
///   • AthleteProfileView → Training Camp card (Activity tab)
///   • ProfileView → Training Plans section (your active camps)
///   • RecordSheet (the +) → "Continue [fighter]'s camp" entry
struct TrainingPlanView: View {
    let athlete: Athlete
    let plan: FighterTrainingPlan

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var pendingSession: TrainingSession?
    @State private var showCampComplete = false

    private var progress: UserTrainingProgress { app.progress(for: plan) }
    private var currentIndex: Int { progress.currentSessionIndex(in: plan) }
    private var fraction: Double { progress.progressFraction(in: plan) }
    private var isComplete: Bool { progress.isComplete(in: plan) }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.md) {
                hero
                if app.showDemoData && !isComplete {
                    demoFastTrack
                }
                sessionList
                Color.clear.frame(height: 80)
            }
            .padding(.horizontal, Theme.Space.md)
            .padding(.top, Theme.Space.sm)
        }
        .background(Theme.Color.bg.ignoresSafeArea())
        .navigationTitle(plan.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $pendingSession) { session in
            SessionLogSheet(
                athlete: athlete,
                session: session,
                onConfirm: { logSession(session) }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(Theme.Radius.xl)
        }
        .alert("Camp complete!",
               isPresented: $showCampComplete) {
            Button("See community", role: .none) { dismiss() }
            Button("Stay here", role: .cancel) {}
        } message: {
            Text("You finished \(plan.title). \(athlete.displayName)'s community just unlocked — head to their profile to see what's inside.")
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                AthleteAvatar(athlete: athlete, size: 56, showsTierRing: false)
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.title)
                        .font(.titleM)
                        .foregroundStyle(Theme.Color.ink)
                        .lineLimit(1)
                    Text(plan.subtitle)
                        .font(.bodyS)
                        .foregroundStyle(Theme.Color.inkSoft)
                        .lineLimit(2)
                }
                Spacer()
            }
            HStack(spacing: 14) {
                progressRing
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(progress.completedSessionKeys.count) of \(plan.sessions.count) complete")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Color.ink)
                    Text(progressSubtitle)
                        .font(.bodyS)
                        .foregroundStyle(Theme.Color.inkSoft)
                }
                Spacer()
            }
        }
        .padding(Theme.Space.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .fill(Theme.Color.bgElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                        .strokeBorder(Theme.Color.stroke, lineWidth: 1)
                )
        )
    }

    private var progressRing: some View {
        ZStack {
            Circle()
                .strokeBorder(Theme.Color.stroke, lineWidth: 5)
                .frame(width: 56, height: 56)
            Circle()
                .trim(from: 0, to: max(0.001, fraction))
                .stroke(
                    Theme.Color.accentDeep,
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 56, height: 56)
                .animation(Theme.Motion.snap, value: fraction)
            Text("\(Int(fraction * 100))%")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Color.ink)
                .monospacedDigit()
        }
    }

    private var progressSubtitle: String {
        if isComplete { return "Camp complete · community unlocked" }
        if currentIndex == 0 { return "Tap session 1 to start" }
        return "Up next: session \(currentIndex + 1) of \(plan.sessions.count)"
    }

    // MARK: - Demo fast-track

    /// Demo-mode shortcut: marks every remaining session complete in
    /// one tap, which cascades through `completeSession` and
    /// auto-unlocks the fighter's community via the existing flow.
    /// Only renders when Profile → "Show demo data" is on so the
    /// real claim path stays honest in normal use.
    private var demoFastTrack: some View {
        Button {
            Haptics.thud()
            advanceCampInDemoMode()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .bold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Complete camp · demo mode")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    Text("Skips session-by-session — unlocks the community immediately")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Theme.Color.accentDeep, Theme.Color.accent],
                        startPoint: .leading, endPoint: .trailing
                    ))
            )
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func advanceCampInDemoMode() {
        // Walk through remaining sessions in order, calling
        // completeSession for each so the auto-unlock-community
        // cascade fires on the last one (same code path as normal
        // completion). Loop fence on currentIndex prevents infinite
        // recursion if the plan is somehow empty.
        var safety = plan.sessions.count
        while safety > 0 {
            let updated = app.progress(for: plan)
            let next = updated.currentSessionIndex(in: plan)
            guard next < plan.sessions.count else { break }
            let session = plan.sessions[next]
            let didFinish = app.completeSession(session, in: plan)
            if didFinish {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    showCampComplete = true
                }
                break
            }
            safety -= 1
        }
        Haptics.success()
    }

    // MARK: - Session list

    private var sessionList: some View {
        VStack(spacing: 8) {
            ForEach(plan.sessions) { session in
                sessionRow(session)
            }
        }
    }

    private func sessionRow(_ session: TrainingSession) -> some View {
        let isCompleted = progress.completedSessionKeys.contains(session.stableKey)
        let isCurrent = session.index == currentIndex && !isComplete
        let isLocked = session.index > currentIndex
        return Button {
            guard isCurrent else { return }
            Haptics.tap()
            pendingSession = session
        } label: {
            HStack(spacing: 14) {
                statusBadge(isCompleted: isCompleted, isCurrent: isCurrent, isLocked: isLocked,
                            number: session.index + 1)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(session.title)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.Color.ink)
                            .lineLimit(1)
                        intensityChip(session.intensity)
                    }
                    Text(session.summary)
                        .font(.bodyS)
                        .foregroundStyle(Theme.Color.inkSoft)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    metaLine(session)
                }
                Spacer()
                if isCurrent {
                    HStack(spacing: 4) {
                        Text("Start")
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Color.accentInk)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(Theme.Color.accent))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(isCurrent ? Theme.Color.accent.opacity(0.08) : Theme.Color.bgElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                            .strokeBorder(
                                isCurrent ? Theme.Color.accent.opacity(0.45) : Theme.Color.stroke,
                                lineWidth: 1
                            )
                    )
            )
            .opacity(isLocked ? 0.55 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(!isCurrent)
    }

    private func statusBadge(isCompleted: Bool, isCurrent: Bool, isLocked: Bool, number: Int) -> some View {
        ZStack {
            Circle()
                .fill(isCompleted ? Theme.Color.accent.opacity(0.20)
                      : isCurrent ? Theme.Color.accent
                      : Theme.Color.surface)
                .frame(width: 38, height: 38)
            if isCompleted {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.Color.accentDeep)
            } else if isLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.Color.inkFaint)
            } else {
                Text("\(number)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(isCurrent ? Theme.Color.accentInk : Theme.Color.inkSoft)
            }
        }
    }

    private func intensityChip(_ intensity: TrainingSession.Intensity) -> some View {
        Text(intensity.label)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .tracking(0.06)
            .textCase(.uppercase)
            .foregroundStyle(Theme.Color.inkSoft)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(
                Capsule().fill(Theme.Color.surface)
            )
    }

    private func metaLine(_ session: TrainingSession) -> some View {
        HStack(spacing: 8) {
            Label("\(session.targetMinutes) min", systemImage: "clock")
                .labelStyle(.titleAndIcon)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.Color.inkFaint)
            Label(session.workoutType.capitalized, systemImage: "figure.run")
                .labelStyle(.titleAndIcon)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.Color.inkFaint)
        }
    }

    // MARK: - Logging

    @MainActor
    private func logSession(_ session: TrainingSession) {
        let justFinished = app.completeSession(session, in: plan)
        Haptics.success()
        if justFinished {
            // Tiny delay so the row visibly flips to "completed"
            // before the celebration alert pops.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                showCampComplete = true
            }
        }
    }
}

// MARK: - Session log sheet

/// Apple-Fitness-style workout card. Video at the top (tap the
/// fullscreen icon in the YouTube player to expand into landscape),
/// numbered step-by-step instructions below, and the "Mark session
/// complete" CTA pinned to the footer. Phase 2 swaps the manual
/// completion for live recorder / HealthKit matching.
struct SessionLogSheet: View {
    let athlete: Athlete
    let session: TrainingSession
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    videoPlayer
                    sessionHeader
                    metaRow
                    stepsBlock
                    coachingNote
                    // Trailing space so the pinned CTA never covers
                    // the last step.
                    Color.clear.frame(height: 130)
                }
            }
            footer
        }
        .background(Theme.Color.bg.ignoresSafeArea())
    }

    // MARK: - Video

    private var videoPlayer: some View {
        ZStack(alignment: .topTrailing) {
            // Fixed height keeps the WebView from collapsing inside
            // the ScrollView. ~16:9 on a typical phone width — taps
            // on the YouTube player's fullscreen button rotate into
            // landscape automatically.
            YouTubeEmbed(watchURL: session.videoURL)
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .background(Color.black)
            HStack(spacing: 4) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 9, weight: .bold))
                Text("Demo footage")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(.black.opacity(0.55)))
            .padding(10)
            // Hint that the player goes fullscreen on rotation.
            .accessibilityLabel("Tap the fullscreen icon to watch in landscape.")
        }
    }

    // MARK: - Header / meta

    private var sessionHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                AthleteAvatar(athlete: athlete, size: 36, showsTierRing: false)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Session \(session.index + 1) · \(athlete.displayName)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(0.06)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.Color.inkFaint)
                    Text(session.title)
                        .font(.titleL)
                        .foregroundStyle(Theme.Color.ink)
                        .lineLimit(2)
                }
            }
            Text(session.summary)
                .font(.bodyM)
                .foregroundStyle(Theme.Color.inkSoft)
                .lineSpacing(2)
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.top, Theme.Space.md)
    }

    private var metaRow: some View {
        HStack(spacing: 10) {
            metaChip(icon: "clock", label: "\(session.targetMinutes) min")
            metaChip(icon: "flame.fill", label: session.intensity.label)
            metaChip(icon: "figure.run", label: session.workoutType.capitalized)
        }
        .padding(.horizontal, Theme.Space.lg)
    }

    private func metaChip(icon: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(Theme.Color.inkSoft)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(
            Capsule().fill(Theme.Color.bgElevated)
                .overlay(Capsule().strokeBorder(Theme.Color.stroke, lineWidth: 1))
        )
    }

    // MARK: - Steps

    private var stepsBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Step by step")
                .font(.titleM)
                .foregroundStyle(Theme.Color.ink)
            ForEach(Array(session.steps.enumerated()), id: \.offset) { idx, step in
                stepRow(number: idx + 1, body: step)
            }
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.top, Theme.Space.sm)
    }

    private func stepRow(number: Int, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.Color.accent.opacity(0.18))
                    .frame(width: 28, height: 28)
                Text("\(number)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Color.accentDeep)
                    .monospacedDigit()
            }
            Text(body)
                .font(.bodyM)
                .foregroundStyle(Theme.Color.ink)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Coaching note

    private var coachingNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "quote.opening")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.Color.accentDeep)
            Text("Move with intent. Quality over reps. Better to do four perfect rounds than eight sloppy ones.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .italic()
                .foregroundStyle(Theme.Color.inkSoft)
                .lineSpacing(2)
        }
        .padding(Theme.Space.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Theme.Color.accent.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .strokeBorder(Theme.Color.accent.opacity(0.25), lineWidth: 1)
                )
        )
        .padding(.horizontal, Theme.Space.lg)
        .padding(.top, Theme.Space.sm)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 8) {
            PrimaryButton(
                title: "Mark session complete",
                icon: "checkmark.circle.fill",
                tint: Theme.Color.accent,
                fg: Theme.Color.accentInk
            ) {
                onConfirm()
                dismiss()
            }
            Button("Not yet") { dismiss() }
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.Color.inkSoft)
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.top, 12)
        .padding(.bottom, Theme.Space.md)
        .background(
            // Soft fade so steps under the CTA aren't a hard cut.
            LinearGradient(
                colors: [Theme.Color.bg.opacity(0), Theme.Color.bg, Theme.Color.bg],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }
}
