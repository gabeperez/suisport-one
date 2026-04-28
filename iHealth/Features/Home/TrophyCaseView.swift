import SwiftUI

struct TrophyCaseView: View {
    @Environment(SocialDataService.self) private var social
    @State private var filter: TrophyCategory? = nil
    @State private var selected: Trophy?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                headline
                categoryFilter
                grid
                Color.clear.frame(height: 80)
            }
            .padding(.horizontal, Theme.Space.md)
            .padding(.top, Theme.Space.sm)
        }
        .background(Theme.Color.bg.ignoresSafeArea())
        .navigationTitle("Trophies")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $selected) { t in
            TrophyDetailSheet(trophy: t)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(Theme.Radius.xl)
        }
    }

    private var headline: some View {
        let unlocked = social.trophies.filter { $0.isUnlocked }.count
        let claimable = social.trophies.filter { $0.isClaimable }.count
        let total = social.trophies.count
        return VStack(alignment: .leading, spacing: 4) {
            Text("\(unlocked) of \(total) unlocked")
                .font(.displayS)
                .foregroundStyle(Theme.Color.ink)
            if claimable > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .bold))
                    Text("\(claimable) ready to claim")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(Theme.Color.accentDeep)
            } else {
                Text("Soulbound to your SuiSport ONE profile. They're yours, forever.")
                    .font(.bodyM).foregroundStyle(Theme.Color.inkSoft)
            }
        }
    }

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(title: "All", isSelected: filter == nil) { filter = nil }
                ForEach(TrophyCategory.allCases, id: \.self) { c in
                    filterChip(title: c.title, isSelected: filter == c) {
                        filter = (filter == c ? nil : c)
                    }
                }
            }
        }
    }

    private func filterChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.select(); action()
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(isSelected ? Theme.Color.inkInverse : Theme.Color.ink)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(
                    Capsule().fill(isSelected ? Theme.Color.ink : Theme.Color.bgElevated)
                )
        }
        .buttonStyle(.plain)
    }

    private var grid: some View {
        let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return LazyVGrid(columns: cols, spacing: 12) {
            ForEach(filteredTrophies) { t in
                Button { selected = t } label: { TrophyCard(trophy: t) }
                    .buttonStyle(.plain)
            }
        }
    }

    private var filteredTrophies: [Trophy] {
        guard let f = filter else { return social.trophies }
        return social.trophies.filter { $0.category == f }
    }
}

// MARK: - Trophy card (large)

struct TrophyCard: View {
    let trophy: Trophy

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            medallion
            Text(trophy.title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Color.ink)
                .lineLimit(1)
            Text(trophy.subtitle)
                .font(.bodyS)
                .foregroundStyle(Theme.Color.inkSoft)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            rarityRow
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.lg).fill(Theme.Color.bgElevated))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .strokeBorder(trophy.isLocked ? Theme.Color.stroke : trophy.rarity.tint.opacity(0.4),
                              lineWidth: trophy.isLocked ? 1 : 1.5)
        )
    }

    private var medallion: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    trophy.isLocked
                    ? LinearGradient(colors: [Theme.Color.surface, Theme.Color.bgElevated],
                                     startPoint: .topLeading, endPoint: .bottomTrailing)
                    : LinearGradient(colors: trophy.gradient.isEmpty ? [Theme.Color.accent, Theme.Color.accentDeep]
                                                                     : trophy.gradient,
                                     startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(height: 104)
            Image(systemName: trophy.icon)
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(trophy.isLocked ? Theme.Color.inkFaint : .white)
                .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
            if trophy.isLocked {
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(Circle().fill(Color.black.opacity(0.35)))
                    }
                    Spacer()
                }
                .padding(6)
            } else if trophy.isClaimable {
                VStack {
                    HStack {
                        Spacer()
                        HStack(spacing: 3) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 9, weight: .bold))
                            Text("Claim")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(Color.black.opacity(0.45)))
                    }
                    Spacer()
                }
                .padding(6)
            }
        }
    }

    private var rarityRow: some View {
        HStack {
            HStack(spacing: 4) {
                Circle().fill(trophy.rarity.tint).frame(width: 6, height: 6)
                Text(trophy.rarity.title)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(trophy.rarity.tint)
            }
            Spacer()
            if trophy.isLocked {
                Text("\(Int(trophy.progress * 100))%")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Color.inkSoft)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.Color.accentDeep)
            }
        }
    }
}

// MARK: - Small trophy chip (for preview strips)

struct TrophyChip: View {
    let trophy: Trophy
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(trophy.isLocked
                          ? LinearGradient(colors: [Theme.Color.surface, Theme.Color.bgElevated],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                          : LinearGradient(colors: trophy.gradient.isEmpty ? [Theme.Color.accent, Theme.Color.accentDeep]
                                                                           : trophy.gradient,
                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 64, height: 64)
                Image(systemName: trophy.icon)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(trophy.isLocked ? Theme.Color.inkFaint : .white)
                if trophy.isClaimable {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "sparkles")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(4)
                                .background(Circle().fill(Color.black.opacity(0.45)))
                        }
                        Spacer()
                    }
                    .frame(width: 64, height: 64)
                    .padding(2)
                }
            }
            Text(trophy.title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.Color.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
    }
}

// MARK: - Trophy detail sheet

struct TrophyDetailSheet: View {
    let trophy: Trophy
    @Environment(AppState.self) private var app
    @Environment(SocialDataService.self) private var social
    @State private var showShare = false
    @State private var claimError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            hero
            meta
            if trophy.isLocked {
                progress
            }
            description
            Spacer()
            footerButton
        }
        .padding(Theme.Space.lg)
        .sheet(isPresented: $showShare) {
            ShareSheet(items: [shareText])
        }
        .alert("Couldn't claim trophy",
               isPresented: Binding(
                   get: { claimError != nil },
                   set: { if !$0 { claimError = nil } }
               )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(claimError ?? "")
        }
    }

    @ViewBuilder
    private var footerButton: some View {
        if trophy.isUnlocked {
            PrimaryButton(title: "Share", icon: "square.and.arrow.up",
                          tint: Theme.Color.ink, fg: Theme.Color.inkInverse) {
                showShare = true
            }
        } else if trophy.isClaimable {
            PrimaryButton(title: "Claim trophy",
                          icon: "sparkles",
                          tint: Theme.Color.accent,
                          fg: Theme.Color.accentInk) {
                claim()
            }
            Text("Saves the qualifying workout on Sui (if it isn't already) and adds the trophy to your profile.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Color.inkFaint)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    @MainActor
    private func claim() {
        Haptics.thud()
        guard let workoutId = trophy.qualifyingWorkoutId,
              let workout = app.workouts.first(where: { $0.id == workoutId })
        else {
            claimError = "Couldn't find the qualifying workout. Try refreshing."
            Haptics.warn()
            return
        }
        // Trophy unlocks instantly — Apple Health is already proof
        // the user did the work. The chain step (if needed) runs
        // quietly in the background; the user doesn't have to wait
        // on it to enjoy the trophy.
        social.markTrophyClaimed(stableKey: trophy.stableKey)
        Haptics.success()

        // If the qualifying workout is already on chain, we're done.
        if let digest = workout.suiTxDigest, !digest.isEmpty { return }

        // Otherwise mint it in the background. We're fire-and-forget
        // here — failures don't roll back the trophy. If the chain
        // step fails the user can still trigger a retry from the
        // workout-detail "Claim Sweat" button, which has the
        // celebration animation + visible error handling.
        Task { await backgroundMint(workout) }
    }

    private func backgroundMint(_ workout: Workout) async {
        do {
            let resp = try await app.mintWorkout(workout)
            if !resp.txDigest.hasPrefix("pending_") {
                social.markFeedItemMinted(
                    workoutId: workout.id,
                    digest: resp.txDigest,
                    walrusBlobId: resp.walrusBlobId
                )
            }
        } catch let api as APIError {
            // Server says it's already in D1 even though we don't
            // have the digest locally — mark already-logged so the
            // upload sheet hides this row from the selectable list.
            if case .server(422, let body) = api,
               let reason = parseRejectReason(body),
               reason == "duplicate_submission" || reason == "duplicate" {
                app.alreadyLoggedWorkoutIDs.insert(workout.id)
            }
            // Anything else: stay silent. The trophy is already on
            // the user's profile; they can retry the chain step
            // from the workout detail view if they care.
        } catch {
            // Same — silent.
        }
    }

    private func describeAPIError(_ err: APIError) -> String {
        switch err {
        case .notImplemented: return "Claiming isn't available yet."
        case .transport(let e): return e.localizedDescription
        case .server(let code, let msg):
            if let friendly = friendlyValidationMessage(body: msg) {
                return friendly
            }
            return msg.isEmpty ? "Server error (\(code))" : msg
        }
    }

    private func parseRejectReason(_ body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj["reason"] as? String
    }

    /// Translate a Zod `validation_error` body into a single-line
    /// human message instead of dumping the raw issue array.
    private func friendlyValidationMessage(body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (obj["error"] as? String) == "validation_error"
        else { return nil }
        return "This workout's data is out of range and can't be saved on Sui. The HealthKit reading may be a corrupted aggregate — try a different workout."
    }

    private var shareText: String {
        "I just unlocked \(trophy.title) on SuiSport ONE — \(trophy.subtitle). Verified on Sui. suisport.app"
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        trophy.isLocked
                        ? LinearGradient(colors: [Theme.Color.surface, Theme.Color.bgElevated],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: trophy.gradient.isEmpty ? [Theme.Color.accent, Theme.Color.accentDeep]
                                                                          : trophy.gradient,
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 96, height: 96)
                Image(systemName: trophy.icon)
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(trophy.isLocked ? Theme.Color.inkFaint : .white)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(trophy.title).font(.displayS).foregroundStyle(Theme.Color.ink)
                HStack(spacing: 6) {
                    Circle().fill(trophy.rarity.tint).frame(width: 6, height: 6)
                    Text(trophy.rarity.title)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(trophy.rarity.tint)
                    Text("·").foregroundStyle(Theme.Color.inkFaint)
                    Text(trophy.category.title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.Color.inkSoft)
                }
            }
            Spacer()
        }
        .padding(.top, Theme.Space.md)
    }

    private var meta: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let earned = trophy.earnedAt {
                row("Earned", Self.fmt.string(from: earned))
            }
            Divider()
            row("Soulbound to", "your Sui address")
        }
        .padding(Theme.Space.md)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.md).fill(Theme.Color.bgElevated))
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.labelBold).foregroundStyle(Theme.Color.inkSoft)
            Spacer()
            Text(v).font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.Color.ink)
        }
        .padding(.vertical, 8)
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Progress")
                    .font(.labelBold).foregroundStyle(Theme.Color.inkSoft)
                Spacer()
                Text("\(Int(trophy.progress * 100))%")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Color.ink)
            }
            ProgressBar(progress: trophy.progress, tint: trophy.rarity.tint)
                .frame(height: 10)
        }
    }

    private var description: some View {
        Text(trophy.subtitle)
            .font(.bodyM)
            .foregroundStyle(Theme.Color.inkSoft)
    }

    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; return f
    }()
}
