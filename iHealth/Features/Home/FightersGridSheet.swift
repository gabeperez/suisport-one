import SwiftUI

/// Full roster sheet surfaced from the "View all" tap on the Fighters
/// feed rail. Shows every verified athlete as a tile with their avatar
/// + name; tapping a tile dismisses the sheet and pushes through to
/// AthleteProfileView via the parent's navigation destination.
struct FightersGridSheet: View {
    let fighters: [Athlete]
    let onPick: (Athlete) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var search: String = ""

    private var filtered: [Athlete] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return fighters }
        return fighters.filter {
            $0.displayName.lowercased().contains(q)
                || $0.handle.lowercased().contains(q)
                || ($0.location ?? "").lowercased().contains(q)
        }
    }

    private let cols = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    headline
                    searchField
                    LazyVGrid(columns: cols, spacing: 14) {
                        ForEach(filtered) { fighter in
                            Button {
                                Haptics.tap()
                                onPick(fighter)
                            } label: {
                                tile(fighter)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if filtered.isEmpty {
                        Text("No fighters match that search.")
                            .font(.bodyM)
                            .foregroundStyle(Theme.Color.inkSoft)
                            .frame(maxWidth: .infinity)
                            .padding(.top, Theme.Space.xl)
                    }
                    Color.clear.frame(height: 60)
                }
                .padding(.horizontal, Theme.Space.md)
                .padding(.top, Theme.Space.sm)
            }
            .background(Theme.Color.bg.ignoresSafeArea())
            .navigationTitle("Fighters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
            }
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(fighters.count) verified athletes")
                .font(.displayS)
                .foregroundStyle(Theme.Color.ink)
            Text("Tap a fighter to see their profile, workouts, and trophies.")
                .font(.bodyS)
                .foregroundStyle(Theme.Color.inkSoft)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Color.inkSoft)
            TextField("Search by name or gym", text: $search)
                .font(.bodyM)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Theme.Color.bgElevated)
        )
    }

    private func tile(_ fighter: Athlete) -> some View {
        VStack(spacing: 8) {
            AthleteAvatar(athlete: fighter, size: 78)
            VStack(spacing: 2) {
                Text(fighter.displayName)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Color.ink)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                if let loc = fighter.location, !loc.isEmpty {
                    Text(loc)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.Color.inkFaint)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .fill(Theme.Color.bgElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                        .strokeBorder(Theme.Color.stroke, lineWidth: 1)
                )
        )
    }
}
