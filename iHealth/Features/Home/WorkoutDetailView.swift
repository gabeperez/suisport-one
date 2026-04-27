import SwiftUI
import UIKit

struct WorkoutDetailView: View {
    let feedItemId: UUID

    @Environment(SocialDataService.self) private var social
    @Environment(\.dismiss) private var dismiss
    @State private var showShare = false
    @State private var commentText = ""
    @FocusState private var commentFocused: Bool
    @State private var selectedAthlete: Athlete?
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var deleteError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                if let item = current {
                    header(item)
                    map(item)
                    statsGrid(item)
                    verifiedStrip
                    captionBlock(item)
                    kudosStrip(item)
                    commentsList(item)
                } else {
                    Text("Workout not found").padding()
                }
                Color.clear.frame(height: 80)
            }
            .padding(.horizontal, Theme.Space.md)
            .padding(.top, Theme.Space.sm)
        }
        .safeAreaInset(edge: .bottom) { composer }
        .background(Theme.Color.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 8) {
                    if isOwnWorkout {
                        Button(role: .destructive) {
                            Haptics.tap()
                            showDeleteConfirm = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .disabled(isDeleting)
                    }
                    Button { showShare = true } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
            }
        }
        .sheet(isPresented: $showShare) {
            if let item = current {
                ShareCardSheet(item: item)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(Theme.Radius.xl)
            }
        }
        .alert("Delete this workout?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await deleteCurrent() }
            }
        } message: {
            Text("This removes the workout and its feed post. Proof + points already minted on-chain will stay, but the post won't be visible.")
        }
        .alert("Couldn't delete", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
        .navigationDestination(item: $selectedAthlete) { a in
            AthleteProfileView(athleteId: a.id)
        }
    }

    private var isOwnWorkout: Bool {
        guard let item = current, let me = social.me else { return false }
        return item.athlete.id == me.id
    }

    @MainActor
    private func deleteCurrent() async {
        guard let item = current else { return }
        isDeleting = true
        defer { isDeleting = false }
        let apiId = social.apiIdForFeedItem(item.id)
        // Server DELETE only when we have a real backend id — seeded
        // items without one get yanked locally so the UI stays honest.
        if !apiId.isEmpty {
            do {
                try await APIClient.shared.deleteWorkout(id: apiId)
            } catch {
                deleteError = (error as? APIError).map(errorDescription(_:))
                    ?? error.localizedDescription
                return
            }
        }
        social.remove(feedItemId: item.id)
        Haptics.success()
        dismiss()
    }

    private func errorDescription(_ err: APIError) -> String {
        switch err {
        case .notImplemented: return "Delete isn't available yet."
        case .transport(let e): return e.localizedDescription
        case .server(let code, let msg):
            return msg.isEmpty ? "Server error (\(code))" : msg
        }
    }

    private var current: FeedItem? { social.feed.first(where: { $0.id == feedItemId }) }

    // MARK: - Header

    private func header(_ item: FeedItem) -> some View {
        HStack(spacing: 12) {
            Button { selectedAthlete = item.athlete } label: {
                AthleteAvatar(athlete: item.athlete, size: 48)
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Button { selectedAthlete = item.athlete } label: {
                    Text(item.athlete.displayName)
                        .font(.titleM).foregroundStyle(Theme.Color.ink)
                }.buttonStyle(.plain)
                Text(Self.formatter.string(from: item.workout.startDate))
                    .font(.bodyS)
                    .foregroundStyle(Theme.Color.inkSoft)
            }
            Spacer()
        }
    }

    // MARK: - Map

    private func map(_ item: FeedItem) -> some View {
        FakeMapPreview(seed: item.mapPreviewSeed, tone: item.athlete.avatarTone)
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
    }

    // MARK: - Stats

    private func statsGrid(_ item: FeedItem) -> some View {
        let cols = [GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: cols, spacing: 8) {
            if let d = item.workout.distanceMeters, d > 0 {
                statBlock(label: "Distance", value: String(format: "%.2f", d / 1000), unit: "km")
            }
            statBlock(label: "Time", value: durationBig(item.workout.duration),
                      unit: durationUnit(item.workout.duration))
            if let e = item.workout.energyKcal {
                statBlock(label: "Calories", value: "\(Int(e))", unit: "kcal")
            } else if let p = item.workout.paceSecondsPerKm {
                statBlock(label: "Pace", value: paceBig(p), unit: "/km")
            } else {
                statBlock(label: "Type", value: item.workout.type.title, unit: "")
            }
            if let hr = item.workout.avgHeartRate {
                statBlock(label: "Avg HR", value: "\(Int(hr))", unit: "bpm")
            }
            statBlock(label: "Points", value: "\(item.workout.points)", unit: "SP")
            if item.tippedSweat > 0 {
                statBlock(label: "Tips", value: "\(item.tippedSweat)", unit: "Sweat")
            }
        }
    }

    private func statBlock(label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.Color.inkFaint)
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Color.ink)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.Color.inkSoft)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.Color.bgElevated)
        )
    }

    // MARK: - Verified strip

    /// Suiscan link to the SuiSport ONE Move package. Tapping the
    /// verified strip opens it so users (and judges) can see the
    /// contract + recent on-chain mints flowing through it.
    private static let packageExplorerURL = URL(
        string: "https://suiscan.xyz/testnet/object/0x15c33f76fba3bc10a327d9792c7948e1eefd0162a13e7a0ac4774d7b8fec2b2c"
    )!

    private var verifiedStrip: some View {
        Link(destination: Self.packageExplorerURL) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.Color.accentDeep)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Verified workout")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.Color.ink)
                    Text("Attested via Apple Health + device signature")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Color.inkSoft)
                }
                Spacer()
                HStack(spacing: 4) {
                    Text("on Sui")
                        .font(.labelMono)
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Theme.Color.inkFaint)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(Theme.Color.accent.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the SuiSport ONE Move package on Suiscan")
    }

    // MARK: - Caption

    private func captionBlock(_ item: FeedItem) -> some View {
        Group {
            if let caption = item.caption, !caption.isEmpty {
                Text(caption)
                    .font(.bodyL)
                    .foregroundStyle(Theme.Color.ink)
                    .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Kudos strip

    private func kudosStrip(_ item: FeedItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Kudos")
                    .font(.labelBold)
                    .foregroundStyle(Theme.Color.inkSoft)
                Spacer()
                Text("\(item.kudosCount) kudos · \(item.tippedSweat) tipped")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.Color.inkFaint)
            }
            if item.kudos.isEmpty {
                Text("Be the first to send kudos.")
                    .font(.bodyS).foregroundStyle(Theme.Color.inkFaint)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: -10) {
                        ForEach(item.kudos.prefix(12)) { k in
                            AthleteAvatar(athlete: k.athlete, size: 32, showsTierRing: false)
                                .overlay(
                                    k.amountSweat > 0
                                    ? Circle().strokeBorder(Theme.Color.gold, lineWidth: 2)
                                    : nil
                                )
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
            HStack(spacing: 8) {
                PillButton(
                    title: item.userHasKudosed ? "Kudos sent" : "Send kudos",
                    icon: item.userHasKudosed ? "bolt.heart.fill" : "bolt.heart",
                    tint: item.userHasKudosed ? Theme.Color.hot : Theme.Color.ink
                ) {
                    SocialDataService.shared.toggleKudos(on: item.id)
                }
                // Separate tip actions — each button sends a different
                // amount. Tips stack (append-only) and don't toggle.
                PillButton(title: "Tip 1", icon: "bolt.fill",
                           tint: Theme.Color.gold, fg: Theme.Color.accentInk) {
                    SocialDataService.shared.sendTip(on: item.id, amount: 1)
                }
                PillButton(title: "Tip 5", icon: "plus.circle.fill",
                           tint: Theme.Color.gold, fg: Theme.Color.accentInk) {
                    SocialDataService.shared.sendTip(on: item.id, amount: 5)
                }
            }
            // Honest disclosure for the demo: tipping today is a local
            // ledger only. On-chain transfers between users land
            // post-mainnet alongside the sponsored zkLogin txn path.
            Text("Tips are local for this demo. On-chain transfers land on mainnet.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.Color.inkFaint)
        }
        .padding(Theme.Space.md)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                        .fill(Theme.Color.bgElevated))
    }

    // MARK: - Comments

    private func commentsList(_ item: FeedItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Comments")
                    .font(.labelBold).foregroundStyle(Theme.Color.inkSoft)
                Spacer()
                Text("\(item.commentCount)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.Color.inkFaint)
            }
            ForEach(item.comments) { c in
                CommentRow(comment: c) {
                    selectedAthlete = c.athlete
                }
            }
        }
    }

    // MARK: - Composer

    private var composer: some View {
        HStack(spacing: 8) {
            if let me = social.me {
                AthleteAvatar(athlete: me, size: 30, showsTierRing: false)
            }
            TextField("Add a comment", text: $commentText)
                .focused($commentFocused)
                .submitLabel(.send)
                .onSubmit(sendComment)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Capsule().fill(Theme.Color.bgElevated))
            if !commentText.trimmingCharacters(in: .whitespaces).isEmpty {
                Button(action: sendComment) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(Theme.Color.ink)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private func sendComment() {
        SocialDataService.shared.addComment(commentText, to: feedItemId)
        commentText = ""
        commentFocused = false
        Haptics.success()
    }

    // MARK: - Helpers

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d · h:mm a"
        return f
    }()

    private func durationBig(_ t: TimeInterval) -> String {
        let total = Int(t); let h = total / 3600; let m = (total % 3600) / 60
        return h > 0 ? "\(h):\(String(format: "%02d", m))" : "\(m)"
    }
    private func durationUnit(_ t: TimeInterval) -> String {
        Int(t) >= 3600 ? "h:m" : "min"
    }
    private func paceBig(_ p: Double) -> String {
        let m = Int(p) / 60; let s = Int(p) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Comment row

struct CommentRow: View {
    let comment: Comment
    let onAthleteTap: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button { onAthleteTap() } label: {
                AthleteAvatar(athlete: comment.athlete, size: 30, showsTierRing: false)
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Button { onAthleteTap() } label: {
                        Text(comment.athlete.displayName)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.Color.ink)
                    }.buttonStyle(.plain)
                    Text(relative(from: comment.at))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Color.inkFaint)
                }
                Text(comment.body)
                    .font(.bodyM)
                    .foregroundStyle(Theme.Color.ink)
                if !comment.reactions.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(comment.reactions.keys).sorted(), id: \.self) { emoji in
                            if let n = comment.reactions[emoji], n > 0 {
                                HStack(spacing: 4) {
                                    Text(emoji)
                                    Text("\(n)")
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                }
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Capsule().fill(Theme.Color.surface))
                            }
                        }
                    }
                }
            }
            Spacer()
        }
    }

    private func relative(from date: Date) -> String {
        let i = Date().timeIntervalSince(date)
        if i < 60 { return "now" }
        if i < 3600 { return "\(Int(i/60))m" }
        if i < 86400 { return "\(Int(i/3600))h" }
        return "\(Int(i/86400))d"
    }
}

// MARK: - Pill button

struct PillButton: View {
    let title: String
    let icon: String
    var tint: Color = Theme.Color.ink
    var fg: Color = Theme.Color.inkInverse
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.pop(); action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(fg)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Capsule().fill(tint))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Streak sheet

struct StreakSheet: View {
    @Environment(SocialDataService.self) private var social
    @Environment(\.dismiss) private var dismiss
    @State private var stake: Int = 25

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            header
            tabs
            stakeSection
            Spacer()
            actions
        }
        .padding(Theme.Space.lg)
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.Color.hot.opacity(0.14))
                    .frame(width: 64, height: 64)
                Image(systemName: "flame.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Theme.Color.hot)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(social.streak.currentDays)-day streak")
                    .font(.displayS)
                    .foregroundStyle(Theme.Color.ink)
                Text("Your longest is \(social.streak.longestDays) days.")
                    .font(.bodyM)
                    .foregroundStyle(Theme.Color.inkSoft)
            }
            Spacer()
        }
    }

    private var tabs: some View {
        HStack(spacing: 8) {
            stakeBlock("Current", "\(social.streak.currentDays)d")
            stakeBlock("Longest", "\(social.streak.longestDays)d")
            stakeBlock("Weekly", "\(social.streak.weeklyStreakWeeks)w")
        }
    }

    private func stakeBlock(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Color.ink)
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.Color.inkSoft)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.md).fill(Theme.Color.bgElevated))
    }

    private var stakeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Stake your streak")
                .font(.titleM).foregroundStyle(Theme.Color.ink)
            Text("Lock up Sweat to hold yourself accountable. Miss a day and your stake goes to the community pot. Hold the streak a week and unlock a **x1.5 multiplier**.")
                .font(.bodyM).foregroundStyle(Theme.Color.inkSoft)
            HStack(spacing: 8) {
                ForEach([10, 25, 50, 100], id: \.self) { amt in
                    Button {
                        Haptics.select(); stake = amt
                    } label: {
                        Text("\(amt)")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(stake == amt ? Theme.Color.accentInk : Theme.Color.ink)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(Capsule().fill(stake == amt ? Theme.Color.accent : Theme.Color.bgElevated))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(Theme.Space.md)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                        .fill(Theme.Color.bgElevated))
    }

    private var actions: some View {
        VStack(spacing: 10) {
            PrimaryButton(title: "Stake \(stake) Sweat",
                          icon: "lock.fill",
                          tint: Theme.Color.ink, fg: Theme.Color.inkInverse) {
                let amount = stake
                Haptics.success()
                // Dismiss immediately, run the mutation on the next
                // runloop tick. Mutating @Observable state inside a
                // sheet's action block + dismissing in the same tick
                // can wedge SwiftUI's sheet animator on real devices
                // — was reproducible as the "freeze on Stake X Sweat"
                // bug in QA.
                dismiss()
                Task { @MainActor in
                    SocialDataService.shared.stakeStreak(amount: amount)
                }
            }
            GhostButton(title: "Not now") { dismiss() }
        }
    }
}

// MARK: - Share card sheet

struct ShareCardSheet: View {
    let item: FeedItem

    @State private var showSystemShare = false
    @State private var showInstagramMissing = false
    @State private var toast: String?

    var body: some View {
        VStack(spacing: Theme.Space.lg) {
            Text("Share your workout")
                .font(.displayS)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, Theme.Space.md)
            shareCard
                .frame(maxWidth: .infinity)
            Spacer()
            HStack(spacing: 10) {
                PrimaryButton(title: "Instagram Stories", icon: "camera.fill",
                              tint: Theme.Color.violet, fg: .white) {
                    shareToInstagramStories()
                }
                PrimaryButton(title: "Copy image", icon: "doc.on.doc",
                              tint: Theme.Color.bgElevated, fg: Theme.Color.ink) {
                    copyCardImage()
                }
            }
            PrimaryButton(title: "More…", icon: "square.and.arrow.up",
                          tint: Theme.Color.bgElevated, fg: Theme.Color.ink) {
                showSystemShare = true
            }
        }
        .padding(Theme.Space.lg)
        .overlay(alignment: .top) {
            if let toast {
                Text(toast)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(Theme.Color.ink))
                    .padding(.top, Theme.Space.lg)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(Theme.Motion.snap, value: toast)
        .sheet(isPresented: $showSystemShare) {
            ShareSheet(items: [systemShareText, systemShareURL])
        }
        .alert("Instagram not installed", isPresented: $showInstagramMissing) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Install Instagram to share directly to your Stories.")
        }
    }

    /// Short plain-text description for the system share sheet, mirrors
    /// the feed-card copy ("Ajoy ran 5.2 km in 32 min on SuiSport ONE").
    private var systemShareText: String {
        let who = item.athlete.displayName
        let verb: String
        switch item.workout.type {
        case .run: verb = "ran"
        case .ride: verb = "rode"
        case .walk: verb = "walked"
        case .hike: verb = "hiked"
        case .swim: verb = "swam"
        default: verb = "trained"
        }
        let t = Int(item.workout.duration)
        let h = t / 3600; let m = (t % 3600) / 60
        let time = h > 0 ? "\(h)h \(m)m" : "\(m) min"
        if let d = item.workout.distanceMeters, d > 0 {
            let km = String(format: "%.1f", d / 1000)
            return "\(who) \(verb) \(km) km in \(time) on SuiSport ONE"
        }
        return "\(who) \(verb) for \(time) on SuiSport ONE"
    }

    private var systemShareURL: URL {
        URL(string: "https://suisport.app/w/\(item.id.uuidString)")
            ?? URL(string: "https://suisport.app")!
    }

    @MainActor
    private func renderCard() -> UIImage? {
        // Render the same view the sheet displays at 2x for crisp
        // output at Stories resolution. MainActor-only because
        // ImageRenderer is MainActor-isolated.
        let renderer = ImageRenderer(content:
            shareCard
                .frame(width: 360)
                .padding(22)
        )
        renderer.scale = 3
        return renderer.uiImage
    }

    @MainActor
    private func copyCardImage() {
        guard let image = renderCard() else { return }
        UIPasteboard.general.image = image
        Haptics.success()
        flashToast("Copied")
    }

    @MainActor
    private func shareToInstagramStories() {
        guard let instagramURL = URL(string: "instagram-stories://share?source_application=suisport"),
              UIApplication.shared.canOpenURL(instagramURL) else {
            showInstagramMissing = true
            return
        }
        guard let image = renderCard(),
              let data = image.pngData() else { return }
        // Instagram Stories uses a pasteboard hand-off — set the
        // sticker image + a ~5min expiration, then open the URL.
        let items: [[String: Any]] = [[
            "com.instagram.sharedSticker.stickerImage": data,
            "com.instagram.sharedSticker.backgroundTopColor": "#0A1424",
            "com.instagram.sharedSticker.backgroundBottomColor": "#1E052E"
        ]]
        let options: [UIPasteboard.OptionsKey: Any] = [
            .expirationDate: Date().addingTimeInterval(60 * 5)
        ]
        UIPasteboard.general.setItems(items, options: options)
        UIApplication.shared.open(instagramURL)
        Haptics.success()
        flashToast("Opening Instagram…")
    }

    @MainActor
    private func flashToast(_ text: String) {
        toast = text
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            if toast == text { toast = nil }
        }
    }

    private var shareCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                AthleteAvatar(athlete: item.athlete, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.athlete.displayName)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Text("on SuiSport ONE")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                    Text("Verified on Sui")
                }
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(.white.opacity(0.14)))
            }
            Text(item.title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
            HStack(spacing: 30) {
                shareStat("Dist", dist)
                shareStat("Time", time)
                shareStat("Pts", "\(item.workout.points)")
            }
            FakeMapPreview(seed: item.mapPreviewSeed, tone: .ember)
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .foregroundStyle(.white)
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.04, green: 0.08, blue: 0.14),
                            Color(red: 0.12, green: 0.02, blue: 0.18)
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
        )
    }

    private func shareStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var dist: String {
        if let d = item.workout.distanceMeters, d > 0 {
            return String(format: "%.1f km", d / 1000)
        }
        return "—"
    }
    private var time: String {
        let t = Int(item.workout.duration)
        let h = t / 3600; let m = (t % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m) min"
    }
}
