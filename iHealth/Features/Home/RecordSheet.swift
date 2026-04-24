import SwiftUI

/// Record-workout sheet. Picks a workout type, then starts a live session.
/// (Live session UI is stubbed — the recorder plumbing is in `WorkoutRecorder`.)
struct RecordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selected: WorkoutType?
    @State private var liveFor: WorkoutType?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Record a workout")
                    .font(.displayS)
                    .foregroundStyle(Theme.Color.ink)
                Text("Pick a type. We'll count it, verify it, and pay you.")
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
        .padding(.horizontal, Theme.Space.lg)
        .padding(.bottom, Theme.Space.lg)
        .fullScreenCover(item: $liveFor) { t in
            LiveRecorderView(type: t)
        }
    }
}

extension WorkoutType: Identifiable {
    public var id: String { rawValue }
}
