import SwiftUI

/// Community section shown on AthleteProfileView when the user
/// switches to the "Community" tab. Two visual states:
///
///   • **Locked** — blurred preview cards + free-preview post + two
///     unlock CTAs (Sweat-spend immediate, training-based stub for
///     Phase 3). The user can see what's behind the gate.
///
///   • **Unlocked** — full post feed sorted newest first.
///
/// Membership is tracked locally via AppState.communityMemberships.
/// Sweat-spend reuses `app.recordRedemption` so the breakdown sheet's
/// "Already redeemed" reflects unlocks.
struct CommunityTab: View {
    let athlete: Athlete
    let community: FighterCommunity
    @Environment(AppState.self) private var app
    @Environment(SocialDataService.self) private var social
    @State private var showUnlockSheet = false
    @State private var insufficientFunds = false

    private var isUnlocked: Bool {
        app.communityMemberships.contains(athlete.id)
    }

    /// Live training-camp progress for this fighter, if a camp exists.
    /// Used to render the "Or train like X" card with real X-of-Y
    /// numbers instead of a hardcoded stub.
    private var trainingFraction: (completed: Int, total: Int)? {
        guard let plan = social.trainingPlans[athlete.id] else { return nil }
        let progress = app.progress(for: plan)
        return (progress.completedSessionKeys.count, plan.sessions.count)
    }

    var body: some View {
        VStack(spacing: Theme.Space.md) {
            if !isUnlocked {
                lockedHero
            } else {
                unlockedHero
            }
            posts
        }
        .sheet(isPresented: $showUnlockSheet) {
            CommunityUnlockSheet(
                athlete: athlete,
                community: community,
                onConfirm: { performUnlock() }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(Theme.Radius.xl)
        }
        .alert("Not enough Sweat", isPresented: $insufficientFunds) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You need \(community.unlockSweatCost) Sweat to join \(athlete.displayName)'s community. Earn more by claiming workouts on chain.")
        }
    }

    // MARK: - Locked hero

    private var lockedHero: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12, weight: .bold))
                Text("Community · members only")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(0.08)
                    .textCase(.uppercase)
            }
            .foregroundStyle(Theme.Color.inkFaint)

            Text(community.description)
                .font(.bodyL)
                .foregroundStyle(Theme.Color.ink)
                .lineSpacing(2)

            Divider().background(Theme.Color.stroke)

            unlockCTAs
        }
        .padding(Theme.Space.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .fill(Theme.Gradient.accent.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                        .strokeBorder(Theme.Color.accent.opacity(0.45), lineWidth: 1)
                )
        )
    }

    private var unlockCTAs: some View {
        VStack(spacing: 10) {
            // Primary path — Sweat-spend, instant unlock. In demo
            // mode the unlock is free and the CTA + flow reflect that
            // honestly so the demo doesn't fake-charge fake Sweat.
            Button {
                Haptics.tap()
                if app.showDemoData {
                    // Demo mode: skip the confirm sheet entirely and
                    // unlock immediately. No Sweat is debited. The
                    // unlock still persists if the user later toggles
                    // demo off — we treat this like a permanent grant.
                    performUnlock()
                } else if app.sweatPoints.total < community.unlockSweatCost {
                    insufficientFunds = true
                } else {
                    showUnlockSheet = true
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: app.showDemoData ? "sparkles" : "bolt.heart.fill")
                        .font(.system(size: 16, weight: .bold))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.showDemoData
                             ? "Unlock free · demo mode"
                             : "Unlock with \(community.unlockSweatCost) Sweat")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                        Text(app.showDemoData
                             ? "Demo toggle is on · no Sweat will be spent"
                             : "Burns Sweat from your wallet · instant access")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.Color.accentInk.opacity(0.8))
                    }
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(Theme.Color.accentInk)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .fill(Theme.Color.accent)
                )
            }
            .buttonStyle(.plain)

            // Sweat-equity path — wired to real per-user training
            // camp progress. Completing the full camp auto-unlocks
            // the community via AppState.completeSession.
            let firstName = athlete.displayName.split(separator: " ").first.map(String.init) ?? "them"
            let completed = trainingFraction?.completed ?? 0
            let total = trainingFraction?.total ?? community.requiredWorkoutCount
            HStack(spacing: 10) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Color.inkSoft)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Or train like \(firstName)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.Color.ink)
                    Text("Complete \(firstName)'s training camp · \(completed)/\(total) sessions done")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Color.inkSoft)
                }
                Spacer()
                if trainingFraction != nil {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.Color.inkSoft)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(Theme.Color.bgElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                            .strokeBorder(Theme.Color.stroke, lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Unlocked hero

    private var unlockedHero: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Theme.Color.accent.opacity(0.20))
                    .frame(width: 36, height: 36)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.Color.accentDeep)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("You're in")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Color.ink)
                Text("Member of \(athlete.displayName)'s community")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Color.inkSoft)
            }
            Spacer()
        }
        .padding(Theme.Space.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .fill(Theme.Color.accent.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                        .strokeBorder(Theme.Color.accent.opacity(0.35), lineWidth: 1)
                )
        )
    }

    // MARK: - Posts

    private var posts: some View {
        VStack(spacing: Theme.Space.sm) {
            // Newest first. When locked, the free preview floats to
            // the top so the unblurred post is the first thing the
            // user sees.
            let sorted = community.posts.sorted { lhs, rhs in
                if !isUnlocked && lhs.isFreePreview != rhs.isFreePreview {
                    return lhs.isFreePreview
                }
                return lhs.createdAt > rhs.createdAt
            }
            ForEach(sorted) { post in
                CommunityPostCard(
                    athlete: athlete,
                    post: post,
                    locked: !isUnlocked
                )
            }
        }
    }

    // MARK: - Unlock action

    @MainActor
    private func performUnlock() {
        // Demo mode bypass: grant the unlock without debiting Sweat.
        // The unlock persists across demo-toggle state because
        // communityMemberships is an independent UserDefaults key —
        // toggling demo back off keeps everything the user unlocked.
        if app.showDemoData {
            app.unlockCommunity(athlete.id)
            showUnlockSheet = false
            Haptics.success()
            return
        }
        let cost = community.unlockSweatCost
        guard app.sweatPoints.total >= cost else {
            insufficientFunds = true
            return
        }
        app.sweatPoints.total = max(0, app.sweatPoints.total - cost)
        app.recordRedemption(cost)
        app.unlockCommunity(athlete.id)
        showUnlockSheet = false
        Haptics.success()
    }
}
