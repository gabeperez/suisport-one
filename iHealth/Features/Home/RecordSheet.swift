import SwiftUI

/// Add-a-workout sheet — the destination of the home-screen + button.
/// Two clean paths:
///   1. **Record a new workout** — pick a type, start the live recorder.
///   2. **Upload a past workout** — pick a HealthKit session you've
///      already done and save it.
///
/// The on-chain story sits in the disclosure line at the bottom —
/// "Saved on Sui." — so the app reads as a normal fitness app to a
/// non-crypto user but carries the Web3 backbone for those who care.
struct RecordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app

    @State private var selected: WorkoutType?
    @State private var liveFor: WorkoutType?
    @State private var showUploadPicker = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                heading
                primaryActions
                divider
                pickerHeading
                grid
                startButton
                onChainDisclosure
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.top, Theme.Space.md)
            .padding(.bottom, Theme.Space.lg)
        }
        .fullScreenCover(item: $liveFor) { t in
            LiveRecorderView(type: t)
        }
        .sheet(isPresented: $showUploadPicker) {
            UploadPastWorkoutSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(Theme.Radius.xl)
        }
    }

    // MARK: - Heading

    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Add a workout")
                .font(.displayS)
                .foregroundStyle(Theme.Color.ink)
            Text("Record a new session or upload one you've already done.")
                .font(.bodyM)
                .foregroundStyle(Theme.Color.inkSoft)
        }
    }

    // MARK: - Two primary actions
    //
    // Both paths land at the same place — a verified workout in the
    // user's profile. "Record new" goes through the live recorder;
    // "Upload past" picks one of the user's HealthKit workouts and
    // saves it through the same pipeline without re-tracking.

    private var primaryActions: some View {
        VStack(spacing: 10) {
            actionCard(
                title: "Upload a past workout",
                subtitle: app.latestUnmintedWorkout != nil
                    ? "Pick a session from your Apple Health history"
                    : "All caught up — every recent workout is saved",
                icon: "tray.and.arrow.up.fill",
                isPrimary: true,
                disabled: app.latestUnmintedWorkout == nil
            ) {
                Haptics.tap()
                showUploadPicker = true
            }
        }
    }

    private func actionCard(
        title: String, subtitle: String, icon: String,
        isPrimary: Bool, disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(isPrimary ? Theme.Color.accent : Theme.Color.bgElevated)
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(isPrimary ? Theme.Color.accentInk : Theme.Color.inkSoft)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Color.ink)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.Color.inkSoft)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.Color.inkFaint)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .fill(Theme.Color.bgElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .strokeBorder(
                        isPrimary && !disabled
                            ? Theme.Color.accent.opacity(0.5)
                            : Theme.Color.stroke,
                        lineWidth: isPrimary && !disabled ? 1.5 : 1
                    )
            )
            .opacity(disabled ? 0.55 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    // MARK: - Live picker (record new)

    private var divider: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Theme.Color.stroke).frame(height: 1)
            Text("OR")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(0.18)
                .foregroundStyle(Theme.Color.inkFaint)
            Rectangle().fill(Theme.Color.stroke).frame(height: 1)
        }
    }

    private var pickerHeading: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Record a new session")
                .font(.titleM)
                .foregroundStyle(Theme.Color.ink)
            Text("Start a timer for a workout you're about to do.")
                .font(.bodyS)
                .foregroundStyle(Theme.Color.inkSoft)
        }
    }

    private var grid: some View {
        let cols = [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]
        return LazyVGrid(columns: cols, spacing: 10) {
            ForEach(WorkoutType.allCases, id: \.self) { t in
                SelectionChip(title: t.title, icon: t.icon, isSelected: selected == t) {
                    selected = t
                }
            }
        }
    }

    private var startButton: some View {
        PrimaryButton(
            title: selected == nil ? "Pick a workout" : "Start \(selected!.title.lowercased())",
            icon: "play.fill",
            tint: selected == nil ? Theme.Color.bgElevated : Theme.Color.ink,
            fg: selected == nil ? Theme.Color.inkFaint : Theme.Color.inkInverse
        ) {
            guard let t = selected else { return }
            liveFor = t
        }
        .disabled(selected == nil)
    }

    // MARK: - On-chain disclosure
    //
    // The whole crypto layer surfaces here: small print, low key,
    // but explicit. Tapping the link reveals more for curious users.

    private var onChainDisclosure: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.Color.inkFaint)
                .padding(.top, 2)
            Text("Workouts you save are verified on the Sui blockchain — your training, on chain forever.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.Color.inkFaint)
                .lineLimit(3)
        }
        .padding(.top, Theme.Space.sm)
    }
}

extension WorkoutType: Identifiable {
    public var id: String { rawValue }
}
