import SwiftUI

struct PlaceholderView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: Theme.Space.md) {
            Spacer()
            Image(systemName: "hammer.fill")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(Theme.Color.inkFaint)
            Text(title).font(.displayS).foregroundStyle(Theme.Color.ink)
            Text(subtitle)
                .font(.bodyM)
                .foregroundStyle(Theme.Color.inkSoft)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Theme.Color.bg.ignoresSafeArea())
    }
}
