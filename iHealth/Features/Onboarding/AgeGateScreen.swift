import SwiftUI

/// Legal requirement: HealthKit mandates 13+ and the privacy policy
/// reflects that. We capture DOB once during onboarding — stored on
/// the athlete row so parental consent / COPPA scenarios can be
/// handled later without re-prompting compliant users.
///
/// Users under 13 see a friendly block screen. Their athlete row has
/// already been created via the auth step but won't advance past this
/// point — a real implementation would call the delete-me endpoint;
/// for beta we just gate the UI.
struct AgeGateScreen: View {
    @Environment(AppState.self) private var app

    @State private var dob: Date = Self.defaultDOB
    @State private var showPicker: Bool = false

    private static var defaultDOB: Date {
        Calendar.current.date(byAdding: .year, value: -25, to: .now) ?? .now
    }

    private var age: Int {
        Calendar.current.dateComponents([.year], from: dob, to: .now).year ?? 0
    }

    private var isEligible: Bool { age >= 13 }

    var body: some View {
        OnboardingShell(showsBack: true) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    Spacer().frame(height: Theme.Space.md)
                    hero
                    dobField
                    Spacer().frame(height: Theme.Space.md)
                    note
                }
                .padding(.horizontal, Theme.Space.lg)
            }
        } actions: {
            if isEligible {
                PrimaryButton(title: "Continue", icon: "arrow.right",
                              tint: Theme.Color.ink, fg: Theme.Color.inkInverse) {
                    app.setDOB(dob)
                    app.advanceOnboarding()
                }
            } else {
                PrimaryButton(title: "You must be 13+", icon: "lock.fill",
                              tint: Theme.Color.hot, fg: .white) {}
                    .disabled(true)
                Text("HealthKit and SuiSport ONE require athletes to be 13 or older. We'll hold your account until you're eligible.")
                    .font(.footnote)
                    .foregroundStyle(Theme.Color.inkFaint)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Space.md)
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Quick check")
                .font(.displayL)
                .foregroundStyle(Theme.Color.ink)
            Text("When were you born? We need to make sure you're 13+ — a HealthKit rule, not ours.")
                .font(.bodyL)
                .foregroundStyle(Theme.Color.inkSoft)
        }
        .padding(.top, Theme.Space.md)
    }

    private var dobField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Date of birth")
                .font(.labelBold)
                .foregroundStyle(Theme.Color.inkSoft)

            Button {
                Haptics.tap()
                withAnimation(Theme.Motion.snap) { showPicker.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "birthday.cake.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isEligible ? Theme.Color.accentDeep : Theme.Color.hot)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.fmt.string(from: dob))
                            .font(.titleM)
                            .foregroundStyle(Theme.Color.ink)
                        Text(isEligible ? "\(age) years old" : "Under 13 — not eligible")
                            .font(.caption)
                            .foregroundStyle(isEligible ? Theme.Color.inkSoft : Theme.Color.hot)
                    }
                    Spacer()
                    Image(systemName: showPicker ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.Color.inkFaint)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .fill(Theme.Color.bgElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .strokeBorder(isEligible ? Theme.Color.stroke : Theme.Color.hot.opacity(0.5),
                                      lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            if showPicker {
                DatePicker("", selection: $dob,
                           in: ...Date(),
                           displayedComponents: .date)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                            .fill(Theme.Color.bgElevated)
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
    }

    private var note: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(Theme.Color.accentDeep)
                .font(.system(size: 12, weight: .bold))
                .padding(.top, 2)
            Text("Your birthday stays private — we use it to compute your age and never show it. You can delete it any time from Profile → Settings → Delete account.")
                .font(.bodyS)
                .foregroundStyle(Theme.Color.inkSoft)
        }
        .padding(Theme.Space.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Theme.Color.accent.opacity(0.10))
        )
    }

    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        return f
    }()
}

#Preview {
    AgeGateScreen().environment(AppState())
}
