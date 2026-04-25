import SwiftUI

/// Picker over the user's HealthKit history. Lets them tap a past
/// workout and save it to their SuiSport ONE profile (which under
/// the hood writes a Walrus blob + mints SWEAT on Sui — but the UI
/// reads as a normal "Save workout" flow with quiet on-chain
/// disclosure at the end).
struct UploadPastWorkoutSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app

    @State private var selected: Workout?
    @State private var inFlight = false
    @State private var result: AppState.MintResult?

    private var candidates: [Workout] {
        app.workouts
            .sorted { $0.startDate > $1.startDate }
            .prefix(40)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    headline

                    if candidates.isEmpty {
                        emptyState
                    } else {
                        workoutList
                    }

                    if let r = result { resultCard(r) }

                    onChainDisclosure
                    Color.clear.frame(height: 80)
                }
                .padding(.horizontal, Theme.Space.lg)
                .padding(.top, Theme.Space.sm)
            }
            .background(Theme.Color.bg.ignoresSafeArea())
            .navigationTitle("Upload past workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let w = selected {
                    saveBar(w)
                }
            }
        }
    }

    // MARK: - Sections

    private var headline: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Pick a workout")
                .font(.titleM).foregroundStyle(Theme.Color.ink)
            Text("From your Apple Health history. Tap one to save it to your profile.")
                .font(.bodyS).foregroundStyle(Theme.Color.inkSoft)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "heart.slash")
                .font(.system(size: 32))
                .foregroundStyle(Theme.Color.inkFaint)
            Text("No workouts yet")
                .font(.titleM).foregroundStyle(Theme.Color.ink)
            Text("Once Apple Health has a session for you, it'll show up here.")
                .font(.bodyS)
                .foregroundStyle(Theme.Color.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Space.xl)
    }

    private var workoutList: some View {
        VStack(spacing: 8) {
            ForEach(candidates) { w in
                workoutRow(w)
                    .onTapGesture {
                        Haptics.tap()
                        selected = (selected?.id == w.id) ? nil : w
                        result = nil
                    }
            }
        }
    }

    private func workoutRow(_ w: Workout) -> some View {
        let isSelected = selected?.id == w.id
        let isVerified = w.verified
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.Color.bgElevated)
                    .frame(width: 40, height: 40)
                Image(systemName: w.type.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.Color.inkSoft)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(w.type.title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Color.ink)
                    if isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.Color.accentDeep)
                    }
                }
                Text(metaLine(w))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Color.inkSoft)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(w.startDate, style: .relative)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.Color.inkFaint)
                Text("\(w.points) pts")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Color.accentDeep)
            }
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.Color.accent)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(isSelected ? Theme.Color.accent.opacity(0.12) : Theme.Color.bgElevated.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .strokeBorder(
                    isSelected ? Theme.Color.accent.opacity(0.45) : Color.clear,
                    lineWidth: 1.5
                )
        )
    }

    private func metaLine(_ w: Workout) -> String {
        var parts: [String] = []
        let mins = Int(w.duration / 60)
        if mins > 0 { parts.append("\(mins) min") }
        if let d = w.distanceMeters, d > 0 {
            parts.append(String(format: "%.2f km", d / 1000))
        }
        if let kcal = w.energyKcal, kcal > 0 {
            parts.append("\(Int(kcal)) kcal")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Save bar

    @ViewBuilder
    private func saveBar(_ w: Workout) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(w.verified ? "Already saved" : "Ready to save")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(0.12)
                        .foregroundStyle(Theme.Color.inkFaint)
                    Text("\(w.type.title) · \(metaLine(w))")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Color.ink)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    Haptics.pop()
                    Task { await save(w) }
                } label: {
                    HStack(spacing: 6) {
                        if inFlight {
                            ProgressView().progressViewStyle(.circular)
                                .tint(Theme.Color.inkInverse)
                        }
                        Text(inFlight ? "Saving…" : (w.verified ? "Already saved" : "Save"))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(Theme.Color.inkInverse)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(
                        w.verified ? Theme.Color.inkFaint : Theme.Color.ink
                    ))
                }
                .buttonStyle(.plain)
                .disabled(inFlight || w.verified)
            }
            .padding(Theme.Space.md)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Result + disclosure

    @ViewBuilder
    private func resultCard(_ r: AppState.MintResult) -> some View {
        switch r {
        case .success(_, let txDigest):
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.green)
                    Text("Workout saved")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Color.ink)
                }
                if !txDigest.hasPrefix("pending_"),
                   let url = URL(string: "https://suiscan.xyz/testnet/tx/\(txDigest)") {
                    Link(destination: url) {
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                                .font(.system(size: 10, weight: .bold))
                            Text("View proof on Sui")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(Theme.Color.accentDeep)
                    }
                } else {
                    Text("Settling on chain — give it ~30 seconds.")
                        .font(.system(size: 11)).foregroundStyle(Theme.Color.inkFaint)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.md)
                            .fill(Color.green.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md)
                            .strokeBorder(Color.green.opacity(0.3), lineWidth: 1))

        case .alreadyMinted:
            Text("You've already saved this workout.")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Color.inkSoft)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.md)
                                .fill(Theme.Color.bgElevated))

        case .failed(let msg):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.Color.hot)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Couldn't save")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.Color.ink)
                    Text(msg).font(.system(size: 11))
                        .foregroundStyle(Theme.Color.inkSoft)
                        .lineLimit(3)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.md)
                            .fill(Theme.Color.hot.opacity(0.08)))
        }
    }

    private var onChainDisclosure: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.Color.inkFaint)
                .padding(.top, 2)
            Text("Workouts you save are verified on the Sui blockchain — every entry is yours, on chain forever.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.Color.inkFaint)
                .lineLimit(3)
        }
    }

    // MARK: - Action

    @MainActor
    private func save(_ w: Workout) async {
        inFlight = true
        defer { inFlight = false }
        let r = await app.mintWorkoutOnChain(w)
        result = r
        switch r {
        case .success: Haptics.success()
        case .alreadyMinted: Haptics.tap()
        case .failed: Haptics.warn()
        }
    }
}
