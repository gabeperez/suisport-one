import SwiftUI
import UIKit

enum Theme {
    enum Color {
        static let bg = SwiftUI.Color(.systemBackground)
        static let bgElevated = SwiftUI.Color(.secondarySystemBackground)
        static let surface = SwiftUI.Color(.tertiarySystemBackground)

        /// Adaptive primary text — black in light mode, white in dark mode.
        static let ink = SwiftUI.Color(.label)
        static let inkSoft = SwiftUI.Color(.secondaryLabel)
        static let inkFaint = SwiftUI.Color(.tertiaryLabel)

        /// Inverse of `ink` — white in light mode, black in dark mode.
        /// Use as foreground when `ink` is the background (primary buttons,
        /// selected filter chips). Prevents white-on-white in dark mode.
        static let inkInverse = SwiftUI.Color(UIColor { trait in
            trait.userInterfaceStyle == .dark ? .black : .white
        })

        static let accent = SwiftUI.Color(red: 0.23, green: 0.95, blue: 0.48)
        static let accentInk = SwiftUI.Color.black
        /// Deep-green text color that works on muted accent backgrounds.
        /// Adaptive so it stays legible in both modes.
        static let accentDeep = SwiftUI.Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.42, green: 0.95, blue: 0.60, alpha: 1.0)
                : UIColor(red: 0.04, green: 0.45, blue: 0.22, alpha: 1.0)
        })

        static let hot = SwiftUI.Color(red: 1.00, green: 0.36, blue: 0.26)
        static let gold = SwiftUI.Color(red: 1.00, green: 0.78, blue: 0.17)
        static let sky = SwiftUI.Color(red: 0.27, green: 0.67, blue: 1.00)
        static let violet = SwiftUI.Color(red: 0.55, green: 0.35, blue: 1.00)

        static let stroke = SwiftUI.Color(.separator).opacity(0.6)
    }

    enum Gradient {
        static let hero = LinearGradient(
            colors: [
                SwiftUI.Color(red: 0.04, green: 0.14, blue: 0.09),
                SwiftUI.Color(red: 0.02, green: 0.06, blue: 0.05)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        static let accent = LinearGradient(
            colors: [
                SwiftUI.Color(red: 0.27, green: 1.00, blue: 0.55),
                SwiftUI.Color(red: 0.10, green: 0.75, blue: 0.35)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        static let sheen = LinearGradient(
            colors: [
                SwiftUI.Color.white.opacity(0.25),
                SwiftUI.Color.white.opacity(0.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    enum Radius {
        static let sm: CGFloat = 10
        static let md: CGFloat = 16
        static let lg: CGFloat = 22
        static let xl: CGFloat = 28
        static let pill: CGFloat = 999
    }

    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    enum Motion {
        static let snap = Animation.spring(response: 0.35, dampingFraction: 0.78)
        static let soft = Animation.spring(response: 0.6, dampingFraction: 0.85)
        static let bounce = Animation.spring(response: 0.5, dampingFraction: 0.65)
        static let linearFast = Animation.easeOut(duration: 0.18)
    }
}
