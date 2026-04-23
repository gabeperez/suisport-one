import SwiftUI

/// Deterministic "map-like" artwork we render when we don't have an actual
/// map tile to show. Uses the seed to generate a plausibly-meandering path.
struct FakeMapPreview: View {
    let seed: Int
    let tone: AvatarTone
    var shows: ShowsMode = .route

    enum ShowsMode { case route, heatmap }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background gradient
                tone.gradient
                    .opacity(0.22)

                // Latitude/longitude-ish grid
                ForEach(0..<6) { i in
                    let y = CGFloat(i) / 5.0 * geo.size.height
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                    .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                }
                ForEach(0..<8) { i in
                    let x = CGFloat(i) / 7.0 * geo.size.width
                    Path { p in
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: geo.size.height))
                    }
                    .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                }

                // The route
                Path { p in
                    let pts = routePoints(in: geo.size)
                    guard let first = pts.first else { return }
                    p.move(to: first)
                    for pt in pts.dropFirst() {
                        p.addLine(to: pt)
                    }
                }
                .stroke(
                    LinearGradient(
                        colors: [tone.colors.0, tone.colors.1],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round)
                )
                .shadow(color: tone.colors.0.opacity(0.35), radius: 6)
            }
        }
    }

    // MARK: - Route generation

    private func routePoints(in size: CGSize) -> [CGPoint] {
        var rng = SeededRNG(seed: UInt64(abs(seed)))
        let count = 42
        var pts: [CGPoint] = []
        var x: CGFloat = size.width * 0.1
        var y: CGFloat = size.height * (0.3 + rng.nextDouble() * 0.4)
        for _ in 0..<count {
            x += size.width * 0.02 + CGFloat(rng.nextDouble()) * size.width * 0.03
            y += (CGFloat(rng.nextDouble()) - 0.5) * size.height * 0.18
            y = max(size.height * 0.1, min(size.height * 0.9, y))
            pts.append(CGPoint(x: x, y: y))
        }
        return pts
    }
}

struct SeededRNG {
    var state: UInt64
    init(seed: UInt64) { self.state = seed != 0 ? seed : 0xdead_beef }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
    mutating func nextDouble() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}
