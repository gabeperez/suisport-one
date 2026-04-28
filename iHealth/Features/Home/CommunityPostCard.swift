import SwiftUI

/// Single community post card. Renders the kind chip + title + body,
/// plus an embedded YouTube player when the post carries a video URL.
/// The `locked` flag dims + blurs everything except the kind chip and
/// title — locked posts read as "you can see what's here, you just
/// can't open it yet."
struct CommunityPostCard: View {
    let athlete: Athlete
    let post: CommunityPost
    let locked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let url = post.youtubeURL {
                videoEmbed(url)
            }
            Text(post.body)
                .font(.bodyM)
                .foregroundStyle(Theme.Color.ink)
                .lineSpacing(2)
                .blur(radius: locked && !post.isFreePreview ? 6 : 0)
                .opacity(locked && !post.isFreePreview ? 0.5 : 1.0)
            footer
        }
        .padding(Theme.Space.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .fill(Theme.Color.bgElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                        .strokeBorder(Theme.Color.stroke, lineWidth: 1)
                )
        )
        .overlay(alignment: .topTrailing) {
            if post.isFreePreview {
                HStack(spacing: 4) {
                    Image(systemName: "lock.open.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text("Free preview")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                }
                .foregroundStyle(Theme.Color.accentDeep)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(Theme.Color.accent.opacity(0.20)))
                .padding(10)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            AthleteAvatar(athlete: athlete, size: 40, showsTierRing: false)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(athlete.displayName)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Color.ink)
                    if athlete.verified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.Color.accentDeep)
                    }
                }
                Text(Self.dateFormatter.string(from: post.createdAt))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.Color.inkFaint)
            }
            Spacer()
            kindChip
        }
    }

    private var kindChip: some View {
        HStack(spacing: 4) {
            Image(systemName: post.kind.icon)
                .font(.system(size: 10, weight: .bold))
            Text(post.kind.label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
        }
        .foregroundStyle(Theme.Color.inkSoft)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(Theme.Color.surface))
    }

    @ViewBuilder
    private func videoEmbed(_ url: String) -> some View {
        ZStack {
            YouTubeEmbed(watchURL: url)
                .aspectRatio(16/9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                .blur(radius: locked && !post.isFreePreview ? 10 : 0)
                .opacity(locked && !post.isFreePreview ? 0.6 : 1.0)
                .allowsHitTesting(!(locked && !post.isFreePreview))
            if locked && !post.isFreePreview {
                Image(systemName: "lock.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(14)
                    .background(Circle().fill(.black.opacity(0.55)))
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if !post.title.isEmpty && post.title != post.body {
            Text(post.title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(0.06)
                .foregroundStyle(Theme.Color.inkFaint)
                .textCase(.uppercase)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
}
