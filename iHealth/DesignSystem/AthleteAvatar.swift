import SwiftUI

/// Deterministic gradient avatar used everywhere an athlete's face would go.
struct AthleteAvatar: View {
    let athlete: Athlete
    var size: CGFloat = 40
    var showsTierRing: Bool = true

    var body: some View {
        ZStack {
            if showsTierRing {
                Circle()
                    .stroke(athlete.tier.ring, lineWidth: max(1.5, size * 0.045))
                    .frame(width: size + size * 0.14, height: size + size * 0.14)
            }
            Circle()
                .fill(athlete.avatarTone.gradient)
                .frame(width: size, height: size)
                .overlay(
                    Text(initials)
                        .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                )
            if athlete.verified {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: size * 0.28, weight: .bold))
                    .foregroundStyle(Theme.Color.sky)
                    .background(Circle().fill(Color.white).padding(2))
                    .offset(x: size * 0.38, y: size * 0.38)
            }
        }
    }

    private var initials: String {
        let parts = athlete.displayName.split(separator: " ")
        return parts.prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
    }
}

struct KudosCoin: View {
    var size: CGFloat = 20
    var body: some View {
        ZStack {
            Circle().fill(
                LinearGradient(
                    colors: [Theme.Color.gold, Color(red: 0.88, green: 0.52, blue: 0.12)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            Image(systemName: "bolt.heart.fill")
                .font(.system(size: size * 0.54, weight: .bold))
                .foregroundStyle(.white.opacity(0.92))
        }
        .frame(width: size, height: size)
        .shadow(color: Theme.Color.gold.opacity(0.5), radius: size * 0.25, y: 1)
    }
}
