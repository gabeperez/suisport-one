import SwiftUI

struct HeroScreen: View {
    @Environment(AppState.self) private var app
    @State private var pulse = false
    @State private var ringScale: CGFloat = 0.7
    @State private var badgeY: CGFloat = 40
    @State private var badgeOpacity: Double = 0

    var body: some View {
        ZStack {
            Theme.Gradient.hero.ignoresSafeArea()

            // Animated background orbs
            GeometryReader { geo in
                Circle()
                    .fill(Theme.Color.accent.opacity(0.18))
                    .frame(width: 420, height: 420)
                    .blur(radius: 80)
                    .offset(x: -140, y: -200)
                    .scaleEffect(pulse ? 1.15 : 0.9)
                    .animation(.easeInOut(duration: 3.6).repeatForever(autoreverses: true), value: pulse)

                Circle()
                    .fill(Theme.Color.violet.opacity(0.22))
                    .frame(width: 360, height: 360)
                    .blur(radius: 70)
                    .offset(x: geo.size.width - 220, y: geo.size.height - 240)
                    .scaleEffect(pulse ? 0.9 : 1.1)
                    .animation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true), value: pulse)
            }

            VStack(spacing: Theme.Space.xl) {
                Spacer()
                badge
                Spacer().frame(height: Theme.Space.md)
                headline
                Spacer()
                ctas
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.bottom, Theme.Space.xl)
        }
        .onAppear {
            pulse = true
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7).delay(0.1)) {
                ringScale = 1.0
            }
            withAnimation(.spring(response: 0.9, dampingFraction: 0.75).delay(0.25)) {
                badgeY = 0
                badgeOpacity = 1
            }
        }
    }

    // MARK: - Pieces

    private var badge: some View {
        ZStack {
            // Concentric rings
            ForEach(0..<3) { i in
                Circle()
                    .strokeBorder(Theme.Color.accent.opacity(0.35 - Double(i) * 0.08), lineWidth: 1.5)
                    .frame(width: 200 + CGFloat(i) * 48, height: 200 + CGFloat(i) * 48)
                    .scaleEffect(ringScale)
            }

            Circle()
                .fill(Theme.Color.accent)
                .frame(width: 200, height: 200)
                .overlay(
                    Circle().stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                .overlay(
                    Image(systemName: "bolt.heart.fill")
                        .font(.system(size: 78, weight: .bold))
                        .foregroundStyle(Theme.Color.accentInk)
                        .shadow(color: .white.opacity(0.4), radius: 12, y: 2)
                )
                .scaleEffect(ringScale)
                .shadow(color: Theme.Color.accent.opacity(0.5), radius: 40, y: 12)
        }
        .offset(y: badgeY)
        .opacity(badgeOpacity)
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            Text("Train like\na fighter.")
                .font(.displayXL)
                .foregroundStyle(.white)
                .lineSpacing(-6)
                .multilineTextAlignment(.leading)

            Text("Verified training, real rewards,\nbuilt with ONE Championship.")
                .font(.system(size: 17, weight: .regular, design: .default))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var ctas: some View {
        VStack(spacing: 12) {
            PrimaryButton(title: "Get started", tint: Theme.Color.accent, fg: Theme.Color.accentInk) {
                app.advanceOnboarding()
            }
            HStack(spacing: 6) {
                Text("Already have an account?")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.55))
                Button {
                    Haptics.tap()
                    app.advanceOnboarding()
                } label: {
                    Text("Sign in")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
    }
}

#Preview {
    HeroScreen().environment(AppState())
}
