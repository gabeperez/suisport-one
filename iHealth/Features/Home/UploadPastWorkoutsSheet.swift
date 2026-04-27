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
            .navigationTitle("Upload past workouts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Upload failed", isPresented: Binding(
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
        let uploadedCount = app.workouts.filter { $0.suiTxDigest?.isEmpty == false }.count
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "bolt.heart.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.Color.accentDeep)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(app.workouts.count) workouts in your history")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Color.ink)
                Text("\(uploadedCount) saved · \(app.workouts.count - uploadedCount) ready to upload")
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
        // Sort: not-yet-uploaded first, then most recent
        let sorted = app.workouts.sorted { a, b in
            let aUploaded = a.suiTxDigest?.isEmpty == false
            let bUploaded = b.suiTxDigest?.isEmpty == false
            if aUploaded != bUploaded { return !aUploaded }
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
        let isUploaded = w.suiTxDigest?.isEmpty == false
        let isSelected = selected.contains(w.id)
        let canSelect = !isUploaded && (isSelected || selected.count < maxSelection)
        let isCurrentlyUploading = mintingIndex.map { selectedOrdered()[$0].id == w.id } ?? false

        return Button {
            guard !isUploaded, mintingIndex == nil else {
                if isUploaded, let url = txURL(for: w) {
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
                    .foregroundStyle(isUploaded ? Theme.Color.accentDeep : Theme.Color.ink)
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
                trailing(for: w, isUploaded: isUploaded, isSelected: isSelected,
                         canSelect: canSelect, isUploading: isCurrentlyUploading)
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
            .opacity(canSelect || isUploaded || isSelected ? 1.0 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(mintingIndex != nil)
    }

    @ViewBuilder
    private func trailing(
        for w: Workout, isUploaded: Bool, isSelected: Bool,
        canSelect: Bool, isUploading: Bool
    ) -> some View {
        if isUploading {
            ProgressView()
        } else if isUploaded {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 11, weight: .bold))
                Text("Verified")
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
                Text("Uploading \(idx + 1) of \(batchTotal)…")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.Color.inkSoft)
            } else if !selected.isEmpty {
                Text("\(selected.count) of \(maxSelection) selected · verified on Sui")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.Color.inkFaint)
            }
            PrimaryButton(
                title: mintingIndex != nil
                    ? "Uploading…"
                    : (selected.isEmpty ? "Select up to \(maxSelection)"
                       : "Upload \(selected.count) workout\(selected.count == 1 ? "" : "s")"),
                icon: mintingIndex != nil ? nil : "checkmark.seal.fill",
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
                // Surface the actual pipeline failure reason when the
                // chain step didn't land. Way more useful than a
                // vague "pending" — e.g. "sui_failed: TypeMismatch"
                // points us at the real bug.
                let pendingReason: String = {
                    let pipeline = resp.attestation?.pipeline ?? "unknown"
                    if pipeline.hasPrefix("sui_failed:") {
                        let reason = pipeline.replacingOccurrences(of: "sui_failed:", with: "")
                        return "Saved — chain step: \(reason.prefix(80))"
                    }
                    switch pipeline {
                    case "executed":                 return "Verified."
                    case "executed_walrus_pending":  return "Verified · proof archive syncing"
                    case "stubbed":                  return "Saved — chain disabled in this build"
                    case "sui_not_configured":       return "Saved — server not connected to Sui"
                    case "walrus_upload_failed":     return "Saved — proof storage failed"
                    default:                         return "Saved — \(pipeline)"
                    }
                }()
                batchResults.append(MintBatchResult(
                    title: "\(w.type.title) · \(w.points) Sweat",
                    txDigest: digest,
                    error: digest == nil ? pendingReason : nil
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
        case .server(422, let body):
            // Parse the structured rejection reason out of the body
            // via JSON instead of substring match — substring was
            // fragile to whitespace + key ordering changes.
            switch parseRejectReason(body) {
            case "duplicate_submission":
                return "Already saved — chain verification syncing"
            case "points_inflated":
                return "Points too high for the workout duration"
            case "pace_impossible":
                return "Pace flagged as impossible"
            default:
                return "Rejected by server (422)"
            }
        case .server(401, _):
            return "Sign in expired"
        case .server(let code, let msg):
            return "Server error (\(code)): \(msg.prefix(80))"
        case .transport: return "Network error"
        case .notImplemented: return "Not available on this build"
        }
    }

    private func parseRejectReason(_ body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json["reason"] as? String
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
            .navigationTitle("Upload complete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onDone() }
                }
            }
        }
    }

    private var verified: Int { results.filter { $0.txDigest != nil }.count }

    private var successHeader: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(Theme.Color.accentDeep)
            Text("\(verified) of \(results.count) verified")
                .font(.displayS)
                .foregroundStyle(Theme.Color.ink)
            Text("Each workout is saved with its own verification record. Tap any row to view the proof.")
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

