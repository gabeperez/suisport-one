import SwiftUI

// MARK: - Primary button

struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    var isLoading: Bool = false
    var tint: Color = Theme.Color.ink
    var fg: Color = Theme.Color.inkInverse
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.pop()
            action()
        } label: {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView().tint(fg)
                } else {
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 17, weight: .semibold))
                    }
                    Text(title)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                }
            }
            .foregroundStyle(fg)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
        }
        .buttonStyle(PrimaryButtonStyle(tint: tint))
        .disabled(isLoading)
    }
}

/// ButtonStyle variant of the primary button. Uses `configuration.isPressed`
/// for press feedback instead of a competing `onLongPressGesture`, which was
/// stealing touch priority and making the whole screen feel sluggish.
struct PrimaryButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                    .fill(tint)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .shadow(
                color: tint.opacity(0.25),
                radius: configuration.isPressed ? 6 : 14,
                x: 0,
                y: configuration.isPressed ? 3 : 8
            )
            .animation(Theme.Motion.snap, value: configuration.isPressed)
    }
}

// MARK: - Secondary button (text / ghost)

struct GhostButton: View {
    let title: String
    var icon: String? = nil
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 15, weight: .semibold))
                }
                Text(title).font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(Theme.Color.inkSoft)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Card

struct Card<Content: View>: View {
    let content: () -> Content
    init(@ViewBuilder content: @escaping () -> Content) { self.content = content }
    var body: some View {
        content()
            .padding(Theme.Space.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .fill(Theme.Color.bgElevated)
            )
    }
}

// MARK: - Chip selection

struct SelectionChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.select()
            action()
        } label: {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(isSelected ? Theme.Color.accentInk : Theme.Color.ink)
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(isSelected ? Theme.Color.accentInk : Theme.Color.ink)
            }
            .frame(maxWidth: .infinity, minHeight: 96)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .fill(isSelected ? Theme.Color.accent : Theme.Color.bgElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .strokeBorder(
                        isSelected ? Theme.Color.accentInk.opacity(0.1) : Theme.Color.stroke,
                        lineWidth: 1
                    )
            )
            .scaleEffect(isSelected ? 1.0 : 0.985)
        }
        .buttonStyle(.plain)
        .animation(Theme.Motion.snap, value: isSelected)
    }
}

// MARK: - Progress dots (onboarding step indicator)

struct StepDots: View {
    let total: Int
    let index: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i <= index ? Theme.Color.ink : Theme.Color.stroke)
                    .frame(width: i == index ? 22 : 6, height: 6)
                    .animation(Theme.Motion.snap, value: index)
            }
        }
    }
}

// MARK: - Shimmer overlay

struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1.2
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    Theme.Gradient.sheen
                        .rotationEffect(.degrees(20))
                        .offset(x: geo.size.width * phase)
                        .blendMode(.plusLighter)
                }
                .allowsHitTesting(false)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                    phase = 1.6
                }
            }
    }
}
extension View { func shimmer() -> some View { modifier(Shimmer()) } }

// MARK: - Demo chip
// Subtle visual signal that what the user is looking at is seed fixture
// data, not live data from their account. Rendered in feed + profile
// headers while the app is running against local seeds or an API response
// with `isDemo: true`. Tappable → link to clear/re-seed in a future pass.
struct DemoChip: View {
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Theme.Color.accentDeep)
                .frame(width: 5, height: 5)
            Text("DEMO")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(1.0)
        }
        .foregroundStyle(Theme.Color.accentDeep)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Capsule().fill(Theme.Color.accent.opacity(0.18)))
        .overlay(Capsule().strokeBorder(Theme.Color.accentDeep.opacity(0.25), lineWidth: 0.5))
    }
}
