import SwiftUI

struct NameGoalScreen: View {
    @Environment(AppState.self) private var app
    @State private var name: String = ""
    @State private var goal: UserGoal? = nil
    @FocusState private var nameFocused: Bool

    var body: some View {
        OnboardingShell(showsBack: true) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    greeting
                    nameField
                    goalPicker
                    Spacer().frame(height: Theme.Space.xxl)
                }
                .padding(.horizontal, Theme.Space.lg)
            }
        } actions: {
            PrimaryButton(
                title: "Continue",
                icon: "arrow.right",
                tint: Theme.Color.ink,
                fg: Theme.Color.inkInverse
            ) {
                app.setGoal(goal, displayName: name)
                app.advanceOnboarding()
            }
            GhostButton(title: "Skip for now") {
                app.setGoal(nil, displayName: name)
                app.advanceOnboarding()
            }
        }
        .onAppear {
            if let existing = app.currentUser?.displayName, !existing.isEmpty,
               existing != "Athlete" {
                name = existing
            }
        }
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            let hello = (app.currentUser?.displayName).flatMap { first($0) } ?? "Hey there"
            Text("\(hello) —")
                .font(.displayL)
                .foregroundStyle(Theme.Color.ink)
            Text("Tell us who you're doing this for.")
                .font(.bodyL)
                .foregroundStyle(Theme.Color.inkSoft)
        }
        .padding(.top, Theme.Space.md)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your name")
                .font(.labelBold)
                .foregroundStyle(Theme.Color.inkSoft)
            TextField("First name", text: $name)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .focused($nameFocused)
                .font(.titleL)
                .padding(.vertical, 14)
                .padding(.horizontal, 18)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .fill(Theme.Color.bgElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .strokeBorder(nameFocused ? Theme.Color.ink : Theme.Color.stroke,
                                      lineWidth: nameFocused ? 1.5 : 1)
                )
        }
    }

    private var goalPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What are you here for?")
                .font(.labelBold)
                .foregroundStyle(Theme.Color.inkSoft)
                .padding(.top, Theme.Space.sm)
            let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(UserGoal.allCases) { g in
                    SelectionChip(title: g.title, icon: g.icon, isSelected: goal == g) {
                        goal = (goal == g ? nil : g)
                    }
                }
            }
        }
    }

    private func first(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != "Athlete" else { return nil }
        return trimmed.split(separator: " ").first.map(String.init)
    }
}

#Preview {
    NameGoalScreen().environment(AppState())
}
