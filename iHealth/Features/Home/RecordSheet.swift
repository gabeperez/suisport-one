import SwiftUI

/// Hub sheet shown when the user taps + on the bottom tab bar. Two
/// paths: mint historical Apple Health workouts in batch, or start a
/// brand-new live recording session. The mint-past path is featured
/// first because it's how a freshly-signed-in user with hundreds of
/// HealthKit workouts gets multiple Suiscan receipts in seconds.
struct RecordSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var showUploadPast = false
    @State private var showRecordNew = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Add a workout")
                    .font(.displayS)
                    .foregroundStyle(Theme.Color.ink)
                Text("Upload from your Apple Health history, or record a new session live.")
                    .font(.bodyM)
                    .foregroundStyle(Theme.Color.inkSoft)
            }
            .padding(.top, Theme.Space.md)

            mintPastCard
            recordNewCard

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.bottom, Theme.Space.lg)
        .sheet(isPresented: $showUploadPast) {
            UploadPastWorkoutsSheet()
                .presentationDetents([.large])
                .presentationCornerRadius(Theme.Radius.xl)
        }
        .sheet(isPresented: $showRecordNew) {
            WorkoutTypePicker { type in
                showRecordNew = false
                showLive(for: type)
            }
            .presentationDetents([.medium, .large])
            .presentationCornerRadius(Theme.Radius.xl)
        }
        .fullScreenCover(item: $liveFor) { t in
            LiveRecorderView(type: t)
        }
    }

    @State private var liveFor: WorkoutType?

    private func showLive(for type: WorkoutType) {
        // Tiny delay so the type-picker sheet fully dismisses before
        // the fullScreenCover slides up — without this the cover can
        // race the dismissal and end up presenting on a stale stack.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            liveFor = type
        }
    }

    // MARK: - Cards

    private var mintPastCard: some View {
        let uploadable = app.workouts.filter { $0.suiTxDigest?.isEmpty != false }.count
        let uploaded = app.workouts.count - uploadable
        return Button {
            Haptics.pop()
            showUploadPast = true
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    badge(text: "FEATURED", tint: Theme.Color.hot)
                    Spacer()
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Text("Upload past workouts")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(app.workouts.isEmpty
                     ? "Backfill from Apple Health to populate your history"
                     : "\(uploadable) ready to upload · \(uploaded) already saved")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))
                HStack(spacing: 8) {
                    chip("Pick up to 5")
                    chip("Verified on Sui")
                    chip("Earn Sweat")
                }
                .padding(.top, 4)
            }
            .padding(Theme.Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack(alignment: .topTrailing) {
                    LinearGradient(
                        colors: [
                            Color(red: 0.06, green: 0.06, blue: 0.07),
                            Color(red: 0.20, green: 0.04, blue: 0.06),
                            Color(red: 0.85, green: 0.02, blue: 0.16),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Circle()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 200, height: 200)
                        .offset(x: 60, y: -80)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(app.workouts.isEmpty)
        .opacity(app.workouts.isEmpty ? 0.6 : 1.0)
    }

    private var recordNewCard: some View {
        Button {
            Haptics.tap()
            showRecordNew = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Theme.Color.accent)
                        .frame(width: 56, height: 56)
                    Image(systemName: "play.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.Color.accentInk)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Record a new session")
                        .font(.titleM).foregroundStyle(Theme.Color.ink)
                    Text("Start an Apple Watch live recording")
                        .font(.bodyS).foregroundStyle(Theme.Color.inkSoft)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Color.inkFaint)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .fill(Theme.Color.bgElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                            .strokeBorder(Theme.Color.stroke, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func badge(text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy, design: .rounded))
            .tracking(0.8)
            .foregroundStyle(.white)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(tint))
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(.white.opacity(0.18)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.20), lineWidth: 0.5))
    }
}

/// Existing workout-type grid, now extracted so RecordSheet can show
/// it as a secondary sheet behind the "Record a new session" card.
private struct WorkoutTypePicker: View {
    let onPick: (WorkoutType) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selected: WorkoutType?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Pick a workout type")
                    .font(.displayS)
                    .foregroundStyle(Theme.Color.ink)
                Text("We'll count it, verify it, and pay you.")
                    .font(.bodyM)
                    .foregroundStyle(Theme.Color.inkSoft)
            }
            .padding(.top, Theme.Space.md)

            let cols = [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ]
            LazyVGrid(columns: cols, spacing: 10) {
                ForEach(WorkoutType.allCases, id: \.self) { t in
                    SelectionChip(title: t.title, icon: t.icon, isSelected: selected == t) {
                        selected = t
                    }
                }
            }

            Spacer()

            PrimaryButton(
                title: selected == nil ? "Pick a type" : "Start \(selected!.title.lowercased())",
                icon: "play.fill",
                tint: selected == nil ? Theme.Color.bgElevated : Theme.Color.ink,
                fg: selected == nil ? Theme.Color.inkFaint : Theme.Color.inkInverse
            ) {
                guard let t = selected else { return }
                onPick(t)
            }
            .disabled(selected == nil)
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.bottom, Theme.Space.lg)
    }
}

extension WorkoutType: Identifiable {
    public var id: String { rawValue }
}
