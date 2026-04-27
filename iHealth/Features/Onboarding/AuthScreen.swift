import SwiftUI

struct AuthScreen: View {
    @Environment(AppState.self) private var app
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("lastAuthProvider") private var lastProviderRaw: String = ""
    @State private var showHowItWorks = false
    @State private var showAllOptions = false

    private enum Provider: String, CaseIterable {
        case apple, google, wallet
    }

    private var lastProvider: Provider? {
        Provider(rawValue: lastProviderRaw)
    }

    /// When we know the user's last-used provider, promote only it plus
    /// a "use a different account" link. When we don't, show all three
    /// as equal siblings.
    private var isReturning: Bool { lastProvider != nil && !showAllOptions }

    var body: some View {
        OnboardingShell(showsBack: true) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    Spacer().frame(height: Theme.Space.md)

                    Text(isReturning ? "Welcome back" : "Welcome")
                        .font(.displayL)
                        .foregroundStyle(Theme.Color.ink)

                    Text(isReturning
                         ? "One tap and you're right back where you left off."
                         : "One tap. No password. No wallet.\nYour points just start adding up.")
                        .font(.bodyL)
                        .foregroundStyle(Theme.Color.inkSoft)

                    Spacer().frame(height: Theme.Space.md)

                    trustRow

                    if let err = app.lastAuthError {
                        authErrorBanner(err)
                    }

                    Spacer().frame(height: Theme.Space.md)
                }
                .padding(.horizontal, Theme.Space.lg)
            }
        } actions: {
            if app.isAuthInFlight {
                inFlightButton
            } else if isReturning, let p = lastProvider {
                primaryButton(for: p)
                Button {
                    Haptics.tap()
                    withAnimation(Theme.Motion.snap) { showAllOptions = true }
                } label: {
                    Text("Use a different account")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.Color.inkFaint)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            } else {
                appleSignInButton
                googleSignInButton
                walletSignInButton
                otherWalletLink

                ageAndTermsDisclosure

                Button {
                    Haptics.tap()
                    showHowItWorks = true
                } label: {
                    Text("How is this free?")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.Color.inkFaint)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .sheet(isPresented: $showHowItWorks) { howItWorksSheet }
        .onAppear {
            // Defensive: a previous wallet sign-in attempt may have
            // been abandoned. Make sure we don't reappear with a
            // stuck spinner and a leaked continuation.
            if app.isAuthInFlight {
                app.cancelPendingAuth()
            }
        }
        .onDisappear {
            // User navigated away mid-flow (back button, app sheet
            // dismiss, etc). Cancel pending wallet auth so the next
            // entry starts clean.
            app.cancelPendingAuth()
        }
    }

    @ViewBuilder
    private func primaryButton(for provider: Provider) -> some View {
        switch provider {
        case .apple:  appleSignInButton
        case .google: googleSignInButton
        case .wallet: walletSignInButton
        }
    }

    private var googleSignInButton: some View {
        Button {
            Haptics.tap()
            Task { await app.signInWithGoogle() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "g.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                Text("Continue with Google")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(Theme.Color.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                    .fill(Theme.Color.bgElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                    .strokeBorder(Theme.Color.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var walletSignInButton: some View {
        Button {
            Haptics.tap()
            Task { await app.signInWithWallet() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "wallet.pass.fill")
                    .font(.system(size: 16, weight: .semibold))
                Text("Connect Sui Wallet")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                Capsule().fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.30, green: 0.65, blue: 0.95),
                            Color(red: 0.15, green: 0.45, blue: 0.80),
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
            )
            .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
            .shadow(color: Color(red: 0.15, green: 0.45, blue: 0.80).opacity(0.35),
                    radius: 14, y: 6)
        }
        .buttonStyle(.plain)
    }

    /// Secondary escape hatch for users who already have a non-Slush
    /// Sui wallet (Suiet, Nightly, etc.) they'd rather sign with.
    /// Opens the bridge page directly in Safari instead of routing
    /// through `my.slush.app/browse/…`; dapp-kit's ConnectButton then
    /// enumerates whatever Wallet-Standard wallets the browser has.
    private var otherWalletLink: some View {
        Button {
            Haptics.tap()
            Task { await app.signInWithWallet(useOtherWallet: true) }
        } label: {
            Text("Use another Sui wallet")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.Color.inkFaint)
                .underline()
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }

    private var inFlightButton: some View {
        VStack(spacing: 8) {
            PrimaryButton(title: "Setting things up…", isLoading: true,
                          tint: Theme.Color.ink, fg: Theme.Color.inkInverse) {}
                .shimmer()
            Button {
                Haptics.tap()
                app.cancelPendingAuth()
            } label: {
                Text("Cancel")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.Color.inkFaint)
                    .underline()
                    .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
    }

    /// HIG-styled Sign in with Apple button. Uses our own `AuthService` flow.
    /// We intentionally don't use `SignInWithAppleButton`: its internal view
    /// has a hard `width <= 375` constraint that conflicts with SwiftUI's
    /// parent hosting-view width on larger iPhones, producing a stream of
    /// "Unable to simultaneously satisfy constraints" logs. A custom button
    /// also lets us reuse the single `AuthService` presentation path instead
    /// of relying on Apple's button completion callback.
    private var appleSignInButton: some View {
        Button {
            Haptics.pop()
            Task { await app.signInWithApple() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 18, weight: .medium))
                Text("Continue with Apple")
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
        }
        .buttonStyle(AppleButtonStyle(colorScheme: colorScheme))
    }

    /// Single line replacing the dedicated AgeGate screen. Strava /
    /// Nike Run Club / every consumer fitness app does it this way —
    /// the sign-in itself is the affirmation, with the legal anchor
    /// sitting underneath for the 13+ HealthKit requirement.
    private var ageAndTermsDisclosure: some View {
        Text("By continuing, you confirm you're 13+ and accept our Terms & Privacy.")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Theme.Color.inkFaint)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
    }

    private func authErrorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.Color.hot)
            VStack(alignment: .leading, spacing: 2) {
                Text("Sign-in failed")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Color.ink)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Color.inkSoft)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Theme.Color.hot.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .strokeBorder(Theme.Color.hot.opacity(0.3), lineWidth: 1)
        )
    }

    private var trustRow: some View {
        HStack(spacing: 10) {
            trustChip(icon: "lock.shield.fill", text: "Private by default")
            trustChip(icon: "checkmark.seal.fill", text: "Verified workouts")
            trustChip(icon: "sparkles", text: "No gas, no fees")
        }
    }

    private func trustChip(icon: String, text: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.Color.accentDeep)
            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.Color.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Theme.Color.accent.opacity(0.12))
        )
    }

    private var howItWorksSheet: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            Text("How it works")
                .font(.displayS)
                .foregroundStyle(Theme.Color.ink)
                .padding(.top, Theme.Space.md)

            row("Train with the fighters",
                "Pick a fighter on the ONE Championship roster, run their official camp — striking, grappling, conditioning, recovery.",
                icon: "figure.martial.arts")
            row("Verified by your Apple Watch",
                "Every session is signed on your device and saved with a verified receipt. No ads. No surveys.",
                icon: "checkmark.seal.fill")
            row("Earn rewards from the fighter",
                "Soulbound trophies signed by the fighter on completion. Plus Sweat and sponsor drops.",
                icon: "trophy.fill")

            Spacer()
            GhostButton(title: "Got it") {}
                .frame(maxWidth: .infinity)
        }
        .padding(Theme.Space.lg)
        .presentationDetents([.medium])
        .presentationCornerRadius(Theme.Radius.xl)
    }

    private func row(_ title: String, _ body: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.Color.accentInk)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Theme.Color.accent))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.titleM).foregroundStyle(Theme.Color.ink)
                Text(body).font(.bodyM).foregroundStyle(Theme.Color.inkSoft)
            }
        }
    }
}

/// Press-animated style for the Apple sign-in button. Uses
/// `configuration.isPressed` so there's no separate gesture recognizer to
/// compete with the button's tap.
struct AppleButtonStyle: ButtonStyle {
    let colorScheme: ColorScheme

    func makeBody(configuration: Configuration) -> some View {
        let bg: Color = colorScheme == .dark ? .white : .black
        let border: Color = colorScheme == .dark
            ? Color.black.opacity(0.05)
            : Color.white.opacity(0.08)
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                    .fill(bg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .shadow(
                color: bg.opacity(0.22),
                radius: configuration.isPressed ? 6 : 14,
                y: configuration.isPressed ? 3 : 8
            )
            .animation(Theme.Motion.snap, value: configuration.isPressed)
    }
}

#Preview {
    AuthScreen().environment(AppState())
}
