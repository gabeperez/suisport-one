import SwiftUI

/// Multi-select sheet for minting past HealthKit workouts on chain.
///
/// Most users land in the app with hundreds of historical workouts
/// already populated by `backfillWorkouts`. Without this sheet they'd
/// have to record a new session to demo the on-chain mint — which is
/// slow and limits the demo to one mint per session. With it, the
/// user can pick up to 5 historical workouts and mint them in
/// sequence; each gets its own unique tx digest + Suiscan link.
///
/// Workouts already on chain (have a `suiTxDigest`) are shown with a
/// "Minted" pill and the row deep-links to that workout's tx, so the
/// user can re-show the receipts during Q&A without remembering
/// which were minted today.
struct UploadPastWorkoutsSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    /// IDs of workouts the user has selected for minting this batch.
    @State private var selected: Set<UUID> = []
    /// Index of the workout currently being submitted (during a batch
    /// mint). nil when not minting.
    @State private var mintingIndex: Int?
    /// Total batch size during a mint, used by the progress label.
    @State private var batchTotal: Int = 0
    /// Per-workout result of the most recent batch — drives the
    /// completion sheet that lists each fresh tx digest.
    @State private var batchResults: [MintBatchResult] = []
    @State private var showResults = false
    @State private var errorMsg: String?

    /// Cap on selection. Keeps gas spend bounded + the demo focused.
    private let maxSelection = 5

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                summaryHeader
                if app.workouts.isEmpty {
                    emptyState
                } else {
                    workoutsList
                }
                bottomBar
            }
            .background(Theme.Color.bg.ignoresSafeArea())
            .navigationTitle("Mint past workouts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Mint failed", isPresented: Binding(
                get: { errorMsg != nil },
                set: { if !$0 { errorMsg = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMsg ?? "")
            }
            .sheet(isPresented: $showResults) {
                BatchResultsSheet(results: batchResults) {
                    showResults = false
                    selected.removeAll()
                }
            }
        }
    }

    // MARK: - Header

    private var summaryHeader: some View {
        let mintedCount = app.workouts.filter { $0.suiTxDigest?.isEmpty == false }.count
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "bolt.heart.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.Color.accentDeep)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(app.workouts.count) workouts in your history")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Color.ink)
                Text("\(mintedCount) on chain · \(app.workouts.count - mintedCount) ready to mint")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Color.inkSoft)
            }
            Spacer()
        }
        .padding(14)
        .background(
            Rectangle()
                .fill(Theme.Color.accent.opacity(0.10))
        )
    }

    // MARK: - List

    private var workoutsList: some View {
        // Sort: unminted first, then most recent
        let sorted = app.workouts.sorted { a, b in
            let aMinted = a.suiTxDigest?.isEmpty == false
            let bMinted = b.suiTxDigest?.isEmpty == false
            if aMinted != bMinted { return !aMinted }
            return a.startDate > b.startDate
        }
        return ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(Array(sorted.enumerated()), id: \.element.id) { index, w in
                    row(w, index: index)
                }
                Color.clear.frame(height: 100)
            }
            .padding(Theme.Space.md)
        }
    }

    private func row(_ w: Workout, index: Int) -> some View {
        let isMinted = w.suiTxDigest?.isEmpty == false
        let isSelected = selected.contains(w.id)
        let canSelect = !isMinted && (isSelected || selected.count < maxSelection)
        let isCurrentlyMinting = mintingIndex.map { selectedOrdered()[$0].id == w.id } ?? false

        return Button {
            guard !isMinted, mintingIndex == nil else {
                if isMinted, let url = txURL(for: w) {
                    UIApplication.shared.open(url)
                }
                return
            }
            Haptics.tap()
            if isSelected { selected.remove(w.id) }
            else if canSelect { selected.insert(w.id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: w.type.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isMinted ? Theme.Color.accentDeep : Theme.Color.ink)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Theme.Color.bgElevated))
                VStack(alignment: .leading, spacing: 2) {
                    Text(w.type.title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.Color.ink)
                    Text(metaLine(for: w))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Color.inkSoft)
                        .lineLimit(1)
                }
                Spacer()
                trailing(for: w, isMinted: isMinted, isSelected: isSelected,
                         canSelect: canSelect, isMinting: isCurrentlyMinting)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(isSelected ? Theme.Color.accent.opacity(0.12) : Theme.Color.bgElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                            .strokeBorder(
                                isSelected ? Theme.Color.accentDeep.opacity(0.5) : Theme.Color.stroke,
                                lineWidth: 1
                            )
                    )
            )
            .opacity(canSelect || isMinted || isSelected ? 1.0 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(mintingIndex != nil)
    }

    @ViewBuilder
    private func trailing(
        for w: Workout, isMinted: Bool, isSelected: Bool,
        canSelect: Bool, isMinting: Bool
    ) -> some View {
        if isMinting {
            ProgressView()
        } else if isMinted {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 11, weight: .bold))
                Text("Minted")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(Theme.Color.accentDeep)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(Theme.Color.accent.opacity(0.18)))
        } else {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22))
                .foregroundStyle(isSelected ? Theme.Color.accentDeep : Theme.Color.inkFaint)
        }
    }

    private func metaLine(for w: Workout) -> String {
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "MMM d · h:mm a"
        let when = dateFmt.string(from: w.startDate)
        let mins = Int(w.duration / 60)
        if let d = w.distanceMeters, d > 0 {
            let km = String(format: "%.1f km", d / 1000)
            return "\(when) · \(km) · \(mins)m · \(w.points) Sweat"
        }
        return "\(when) · \(mins)m · \(w.points) Sweat"
    }

    private func txURL(for w: Workout) -> URL? {
        guard let d = w.suiTxDigest, !d.isEmpty else { return nil }
        return URL(string: "https://suiscan.xyz/testnet/tx/\(d)")
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 6) {
            if let idx = mintingIndex {
                Text("Minting \(idx + 1) of \(batchTotal)…")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.Color.inkSoft)
            } else if !selected.isEmpty {
                Text("\(selected.count) of \(maxSelection) selected")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.Color.inkFaint)
            }
            PrimaryButton(
                title: mintingIndex != nil
                    ? "Minting…"
                    : (selected.isEmpty ? "Select up to \(maxSelection)"
                       : "Mint \(selected.count) workout\(selected.count == 1 ? "" : "s") on Sui"),
                icon: mintingIndex != nil ? nil : "bolt.fill",
                isLoading: mintingIndex != nil,
                tint: selected.isEmpty ? Theme.Color.bgElevated : Theme.Color.ink,
                fg: selected.isEmpty ? Theme.Color.inkFaint : Theme.Color.inkInverse
            ) {
                Task { await mintBatch() }
            }
            .disabled(selected.isEmpty || mintingIndex != nil)
        }
        .padding(Theme.Space.md)
        .background(.ultraThinMaterial)
    }

    // MARK: - Mint flow

    /// Workouts in selection order (most recent first within selection),
    /// used to drive the per-row spinner during a batch mint.
    private func selectedOrdered() -> [Workout] {
        app.workouts
            .filter { selected.contains($0.id) }
            .sorted { $0.startDate > $1.startDate }
    }

    private func mintBatch() async {
        let batch = selectedOrdered()
        guard !batch.isEmpty else { return }
        batchTotal = batch.count
        batchResults = []
        Haptics.thud()
        for (i, w) in batch.enumerated() {
            mintingIndex = i
            do {
                let resp = try await app.mintWorkout(w)
                let digest = resp.txDigest.hasPrefix("pending_") ? nil : resp.txDigest
                batchResults.append(MintBatchResult(
                    title: "\(w.type.title) · \(w.points) Sweat",
                    txDigest: digest,
                    error: digest == nil ? "Not yet on chain (pending retry)" : nil
                ))
            } catch {
                batchResults.append(MintBatchResult(
                    title: "\(w.type.title) · \(w.points) Sweat",
                    txDigest: nil,
                    error: (error as? APIError).map(describeAPIError) ?? error.localizedDescription
                ))
            }
        }
        mintingIndex = nil
        Haptics.success()
        showResults = true
    }

    private func describeAPIError(_ e: APIError) -> String {
        switch e {
        case .server(let code, let msg): return "HTTP \(code) · \(msg.prefix(80))"
        case .transport: return "Network error"
        case .notImplemented: return "Endpoint missing"
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 36))
                .foregroundStyle(Theme.Color.inkFaint)
            Text("No workouts yet")
                .font(.titleM).foregroundStyle(Theme.Color.ink)
            Text("Record a session or grant Apple Health access during onboarding to backfill your history.")
                .font(.bodyS).foregroundStyle(Theme.Color.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Space.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Batch results sheet

/// Per-workout outcome surfaced to the results sheet. File-level
/// type so both the parent state and the results sheet can use it
/// without nested-private gymnastics.
struct MintBatchResult: Identifiable {
    let id = UUID()
    let title: String
    let txDigest: String?
    let error: String?
}

/// Shown after a batch mint completes. One row per selected workout
/// with its tx digest as a Suiscan link, so the user can pull up
/// every fresh receipt during the demo.
private struct BatchResultsSheet: View {
    let results: [MintBatchResult]
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    successHeader
                    ForEach(results) { r in
                        row(r)
                    }
                    Color.clear.frame(height: 60)
                }
                .padding(Theme.Space.md)
            }
            .background(Theme.Color.bg.ignoresSafeArea())
            .navigationTitle("Mint complete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onDone() }
                }
            }
        }
    }

    private var minted: Int { results.filter { $0.txDigest != nil }.count }

    private var successHeader: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(Theme.Color.accentDeep)
            Text("\(minted) of \(results.count) on chain")
                .font(.displayS)
                .foregroundStyle(Theme.Color.ink)
            Text("Each minted workout has its own transaction on Sui — tap any row to verify it on Suiscan.")
                .font(.bodyS)
                .foregroundStyle(Theme.Color.inkSoft)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, Theme.Space.lg)
    }

    private func row(_ r: MintBatchResult) -> some View {
        let url = r.txDigest.flatMap { URL(string: "https://suiscan.xyz/testnet/tx/\($0)") }
        return Group {
            if let url {
                Link(destination: url) { rowContent(r) }
                    .buttonStyle(.plain)
            } else {
                rowContent(r).opacity(0.7)
            }
        }
    }

    @ViewBuilder
    private func rowContent(_ r: MintBatchResult) -> some View {
        HStack(spacing: 12) {
            Image(systemName: r.txDigest != nil ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(r.txDigest != nil ? Theme.Color.accentDeep : Theme.Color.hot)
                .frame(width: 32, height: 32)
                .background(Circle().fill(
                    r.txDigest != nil
                        ? Theme.Color.accent.opacity(0.18)
                        : Theme.Color.hot.opacity(0.18)
                ))
            VStack(alignment: .leading, spacing: 2) {
                Text(r.title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.Color.ink)
                if let d = r.txDigest {
                    Text(shortDigest(d))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.Color.inkSoft)
                        .lineLimit(1)
                } else if let err = r.error {
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Color.hot)
                        .lineLimit(1)
                }
            }
            Spacer()
            if r.txDigest != nil {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Color.inkFaint)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Theme.Color.bgElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .strokeBorder(Theme.Color.stroke, lineWidth: 1)
                )
        )
    }

    private func shortDigest(_ d: String) -> String {
        guard d.count > 16 else { return d }
        return "\(d.prefix(8))…\(d.suffix(6))"
    }
}

