import SwiftUI

/// Off-chain rewards catalog. User spends Sweat Points to reveal a
/// pre-generated code (promo code, gift card, etc.). The server owns
/// the code pool; we just render it + POST to redeem.
///
/// Balance shown here mirrors `AppState.sweatPoints.total`. On
/// successful redeem we optimistically decrement and the server
/// response is authoritative; we also refresh the user's sweat row
/// after so the profile stat pill stays in sync.
struct RewardsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    @State private var items: [RewardCatalogItemDTO] = []
    @State private var history: [RedemptionHistoryItemDTO] = []
    @State private var isLoading = false
    @State private var errorMsg: String?
    @State private var redeemingItem: RewardCatalogItemDTO?
    @State private var revealedCode: RevealedCode?

    struct RevealedCode: Identifiable {
        let id = UUID()
        let title: String
        let code: String
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    balanceHeader

                    if isLoading && items.isEmpty {
                        ProgressView().frame(maxWidth: .infinity)
                            .padding(.top, Theme.Space.xl)
                    } else if let msg = errorMsg, items.isEmpty {
                        errorBlock(msg)
                    } else if items.isEmpty {
                        emptyBlock
                    } else {
                        catalogSection
                    }

                    if !history.isEmpty {
                        historySection
                    }
                }
                .padding(Theme.Space.lg)
            }
            .background(Theme.Color.bg.ignoresSafeArea())
            .navigationTitle("Rewards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $redeemingItem) { item in
                RedeemConfirmSheet(item: item, balance: app.sweatPoints.total) {
                    Task { await redeem(item) }
                }
            }
            .sheet(item: $revealedCode) { reveal in
                CodeRevealSheet(title: reveal.title, code: reveal.code)
            }
            .task { await refresh() }
            .refreshable { await refresh() }
        }
    }

    // MARK: - Sections

    private var balanceHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your balance")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.Color.inkFaint)
                .textCase(.uppercase)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(app.sweatPoints.total)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Color.ink)
                Text("Sweat Points")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Color.inkSoft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.lg)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
                .fill(Theme.Color.accent.opacity(0.15))
        )
    }

    private var catalogSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Redeem").font(.titleM).foregroundStyle(Theme.Color.ink)
            ForEach(items) { item in
                rewardCard(item)
                    .onTapGesture {
                        Haptics.tap()
                        redeemingItem = item
                    }
            }
        }
    }

    private func rewardCard(_ item: RewardCatalogItemDTO) -> some View {
        let affordable = app.sweatPoints.total >= item.costPoints
        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(Theme.Color.bgElevated)
                    .frame(width: 56, height: 56)
                Image(systemName: "gift.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.Color.accentDeep)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.titleM).foregroundStyle(Theme.Color.ink)
                    .lineLimit(1)
                if let sub = item.subtitle {
                    Text(sub)
                        .font(.bodyS).foregroundStyle(Theme.Color.inkSoft)
                        .lineLimit(2)
                }
                if let stock = item.stockRemaining, stock > 0 && stock < 20 {
                    Text("\(stock) left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(item.costPoints)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(affordable ? Theme.Color.ink : Theme.Color.inkFaint)
                Text("points")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.Color.inkFaint)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .fill(Theme.Color.bgElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                        .strokeBorder(Theme.Color.stroke, lineWidth: 1)
                )
        )
        .opacity(affordable ? 1.0 : 0.55)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Redemption history")
                .font(.titleM).foregroundStyle(Theme.Color.ink)
                .padding(.top, Theme.Space.md)
            ForEach(history) { r in
                historyRow(r)
            }
        }
    }

    private func historyRow(_ r: RedemptionHistoryItemDTO) -> some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.title).font(.bodyM).foregroundStyle(Theme.Color.ink)
                Text(Date(timeIntervalSince1970: r.redeemedAt),
                     format: .relative(presentation: .named))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Color.inkFaint)
            }
            Spacer()
            Button {
                Haptics.tap()
                revealedCode = RevealedCode(title: r.title, code: r.code)
            } label: {
                Text("View code")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(Theme.Color.bgElevated))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Theme.Color.bgElevated.opacity(0.5))
        )
    }

    private func errorBlock(_ msg: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 30))
                .foregroundStyle(Theme.Color.inkFaint)
            Text(msg)
                .font(.bodyM).foregroundStyle(Theme.Color.inkSoft)
                .multilineTextAlignment(.center)
            Button("Try again") {
                Task { await refresh() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Space.xl)
    }

    private var emptyBlock: some View {
        VStack(spacing: 10) {
            Image(systemName: "gift")
                .font(.system(size: 36))
                .foregroundStyle(Theme.Color.inkFaint)
            Text("No rewards right now")
                .font(.titleM).foregroundStyle(Theme.Color.ink)
            Text("We're curating the first drop. Keep logging workouts — your points are safe.")
                .font(.bodyS).foregroundStyle(Theme.Color.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Space.xl)
    }

    // MARK: - Data

    private func refresh() async {
        isLoading = true
        errorMsg = nil
        async let catalog = APIClient.shared.fetchRewardsCatalog()
        async let hist    = APIClient.shared.fetchRewardsHistory()
        do {
            let (c, h) = try await (catalog, hist)
            items = c
            history = h
        } catch {
            errorMsg = "Couldn't load rewards — check your connection."
        }
        isLoading = false
    }

    private func redeem(_ item: RewardCatalogItemDTO) async {
        do {
            let resp = try await APIClient.shared.redeemReward(catalogId: item.id)
            // Optimistically decrement + refresh from server in background.
            app.sweatPoints.total = max(0, app.sweatPoints.total - resp.costPoints)
            revealedCode = RevealedCode(title: item.title, code: resp.code)
            await refresh()
        } catch {
            errorMsg = "Redeem failed. Try again in a moment."
        }
        redeemingItem = nil
    }
}

// MARK: - Sheets

private struct RedeemConfirmSheet: View {
    let item: RewardCatalogItemDTO
    let balance: Int
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var affordable: Bool { balance >= item.costPoints }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            Capsule().fill(Theme.Color.stroke).frame(width: 40, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, Theme.Space.sm)

            Image(systemName: "gift.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.Color.accentDeep)
                .frame(maxWidth: .infinity)
                .padding(.top, Theme.Space.md)

            Text(item.title)
                .font(.displayS).foregroundStyle(Theme.Color.ink)
            if let desc = item.description {
                Text(desc).font(.bodyM).foregroundStyle(Theme.Color.inkSoft)
            }

            HStack {
                Text("Cost").font(.bodyM).foregroundStyle(Theme.Color.inkSoft)
                Spacer()
                Text("\(item.costPoints) points")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Color.ink)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                            .fill(Theme.Color.bgElevated))

            HStack {
                Text("After").font(.bodyM).foregroundStyle(Theme.Color.inkSoft)
                Spacer()
                Text("\(max(0, balance - item.costPoints)) points")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(affordable ? Theme.Color.ink : .red)
            }

            Spacer()

            Button {
                Haptics.pop()
                onConfirm()
                dismiss()
            } label: {
                Text(affordable ? "Redeem" : "Not enough points")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(Capsule().fill(affordable ? Theme.Color.accentDeep : Theme.Color.inkFaint))
            }
            .buttonStyle(.plain)
            .disabled(!affordable)
        }
        .padding(Theme.Space.lg)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(Theme.Radius.xl)
    }
}

private struct CodeRevealSheet: View {
    let title: String
    let code: String
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            Capsule().fill(Theme.Color.stroke).frame(width: 40, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, Theme.Space.sm)

            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(Theme.Color.accentDeep)
                .frame(maxWidth: .infinity)

            Text(title)
                .font(.displayS).foregroundStyle(Theme.Color.ink)
                .frame(maxWidth: .infinity, alignment: .center)

            VStack(spacing: 8) {
                Text("YOUR CODE")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.Color.inkFaint)
                    .tracking(0.8)
                Text(code)
                    .font(.system(.title2, design: .monospaced).weight(.bold))
                    .foregroundStyle(Theme.Color.ink)
                    .textSelection(.enabled)
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                                    .fill(Theme.Color.bgElevated))
            }
            .frame(maxWidth: .infinity)

            Button {
                UIPasteboard.general.string = code
                Haptics.tap()
                copied = true
            } label: {
                Label(copied ? "Copied" : "Copy code",
                      systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(Capsule().fill(Theme.Color.accentDeep))
            }
            .buttonStyle(.plain)

            Text("Keep this code safe — you can re-view it from your redemption history.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Color.inkFaint)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Spacer()
        }
        .padding(Theme.Space.lg)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(Theme.Radius.xl)
    }
}

#Preview {
    RewardsView()
        .environment(AppState())
}
