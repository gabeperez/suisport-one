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
    @State private var sampleRedemption: SampleRedemptionResponse?
    @State private var isRedeemingSample = false
    @State private var showTicketConfirm = false
    @State private var redeemErrorMsg: String?

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
                    sampleHeader
                    onChainSampleCard

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
            .sheet(item: $sampleRedemption) { resp in
                SampleRedemptionSheet(response: resp) {
                    sampleRedemption = nil
                }
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
                Text("Sweat")
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

    /// Header label for the in-app catalog. Honest about scope: real
    /// burns are mainnet roadmap; today is sample-only.
    private var sampleHeader: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Color.accentDeep)
            VStack(alignment: .leading, spacing: 2) {
                Text("In-app rewards (sample)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Color.ink)
                Text("Codes are local for this hackathon. Tap the on-chain item below to land a real Sui transaction in your wallet.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Color.inkSoft)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Theme.Color.accent.opacity(0.10))
        )
    }

    /// Featured ONE Championship ticket redemption — branded card,
    /// confirmation flow, on-chain receipt. Drives the demo's
    /// "real value lands on Sui" moment with a clear consumer hook.
    private var onChainSampleCard: some View {
        let canAfford = app.sweatPoints.total >= 1
        return Button {
            guard canAfford, !isRedeemingSample else { return }
            Haptics.pop()
            showTicketConfirm = true
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    HStack(spacing: 6) {
                        Circle().fill(Color(red: 0.85, green: 0.02, blue: 0.16))
                            .frame(width: 6, height: 6)
                        Text("ONE CHAMPIONSHIP")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .tracking(0.20)
                            .foregroundStyle(.white.opacity(0.95))
                    }
                    Spacer()
                    Text("LIVE ON SUI")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Capsule().fill(.white.opacity(0.18)))
                }
                Text("ONE Samurai 1 Ticket")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Wed, Apr 29 · Ariake Arena · Tokyo")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                HStack(alignment: .firstTextBaseline) {
                    Text("1 Sweat")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("redeem")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                    Spacer()
                    if isRedeemingSample {
                        ProgressView().tint(.white)
                    } else {
                        HStack(spacing: 4) {
                            Text("Redeem")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(.white.opacity(0.20)))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                    }
                }
            }
            .padding(Theme.Space.lg)
            .frame(maxWidth: .infinity)
            .background(
                ZStack(alignment: .topTrailing) {
                    LinearGradient(
                        colors: [
                            Color(red: 0.06, green: 0.06, blue: 0.07),
                            Color(red: 0.20, green: 0.04, blue: 0.06),
                            Color(red: 0.85, green: 0.02, blue: 0.16),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Circle()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 180, height: 180)
                        .offset(x: 50, y: -70)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 1)
            )
            .opacity(canAfford ? 1.0 : 0.7)
        }
        .buttonStyle(.plain)
        .disabled(!canAfford || isRedeemingSample)
        .alert("Confirm redemption", isPresented: $showTicketConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Redeem 1 Sweat") {
                Task { await redeemTicket() }
            }
        } message: {
            Text("Redeem 1 Sweat for an ONE Samurai 1 ticket. The redemption will land as a real on-chain transaction on Sui — visible on Suiscan immediately.")
        }
        .alert("Redemption failed", isPresented: Binding(
            get: { redeemErrorMsg != nil },
            set: { if !$0 { redeemErrorMsg = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(redeemErrorMsg ?? "")
        }
    }

    private func redeemTicket() async {
        isRedeemingSample = true
        defer { isRedeemingSample = false }
        do {
            let resp = try await APIClient.shared.redeemSample()
            // Mirror server-side debit on the local Sweat counter so
            // the balance ticks down without a refresh round-trip.
            app.sweatPoints.total = max(0, app.sweatPoints.total - resp.costPoints)
            sampleRedemption = resp
            Haptics.success()
        } catch let api as APIError {
            switch api {
            case .server(402, _):
                redeemErrorMsg = "You need at least 1 Sweat to redeem this ticket."
            case .server(let code, let body):
                redeemErrorMsg = "Server error (\(code)). \(body.prefix(120))"
            case .transport:
                redeemErrorMsg = "Network error. Try again in a moment."
            case .notImplemented:
                redeemErrorMsg = "Redemption isn't available on this build."
            }
            Haptics.warn()
        } catch {
            redeemErrorMsg = error.localizedDescription
            Haptics.warn()
        }
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
                Text("Sweat")
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
            Text("We're curating the first drop. Keep logging workouts — your Sweat is safe.")
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
                Text("\(item.costPoints) Sweat")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Color.ink)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                            .fill(Theme.Color.bgElevated))

            HStack {
                Text("After").font(.bodyM).foregroundStyle(Theme.Color.inkSoft)
                Spacer()
                Text("\(max(0, balance - item.costPoints)) Sweat")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(affordable ? Theme.Color.ink : .red)
            }

            Spacer()

            Button {
                Haptics.pop()
                onConfirm()
                dismiss()
            } label: {
                Text(affordable ? "Redeem" : "Not enough Sweat")
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

/// Success sheet shown after the operator sponsors the SUI transfer
/// for a ticket redemption. Looks like a ticket receipt — branded
/// header, perforated stub, prominent "View on Sui" CTA so the user
/// sees the redemption is real and auditable.
private struct SampleRedemptionSheet: View {
    let response: SampleRedemptionResponse
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.lg) {
                Capsule().fill(Theme.Color.stroke).frame(width: 40, height: 4)
                    .padding(.top, Theme.Space.sm)

                // Ticket card — ONE-branded, looks like a pass.
                ticketCard

                receiptDetails

                if let url = URL(string: response.txExplorerUrl) {
                    Link(destination: url) {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 16, weight: .bold))
                            Text("View transaction on Sui")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        .background(
                            Capsule().fill(LinearGradient(
                                colors: [
                                    Color(red: 0.30, green: 0.65, blue: 0.95),
                                    Color(red: 0.15, green: 0.45, blue: 0.80),
                                ],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                        )
                        .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }

                if let walletURL = URL(string: response.walletExplorerUrl) {
                    Link(destination: walletURL) {
                        Text("View your wallet on Suiscan")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.Color.inkSoft)
                            .underline()
                    }
                    .buttonStyle(.plain)
                }

                Text(response.message)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Color.inkFaint)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Space.md)

                PrimaryButton(
                    title: "Done",
                    tint: Theme.Color.ink,
                    fg: Theme.Color.inkInverse
                ) {
                    Haptics.tap()
                    onDone()
                }

                Color.clear.frame(height: 12)
            }
            .padding(Theme.Space.lg)
        }
        .background(Theme.Color.bg.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationCornerRadius(Theme.Radius.xl)
        .onAppear { Haptics.success() }
    }

    private var ticketCard: some View {
        VStack(spacing: 0) {
            // Top half: event details
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 6) {
                        Circle().fill(Color(red: 0.85, green: 0.02, blue: 0.16))
                            .frame(width: 6, height: 6)
                        Text("ONE CHAMPIONSHIP")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .tracking(0.18)
                            .foregroundStyle(.white.opacity(0.92))
                    }
                    Spacer()
                    Text("ADMIT ONE")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.7))
                }

                Text("ONE Samurai 1")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                HStack(spacing: 18) {
                    ticketField(label: "Date", value: "Apr 29")
                    ticketField(label: "Venue", value: "Ariake")
                    ticketField(label: "City", value: "Tokyo")
                }
                .padding(.top, 4)
            }
            .padding(Theme.Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Perforation
            HStack(spacing: 6) {
                Circle().fill(Theme.Color.bg).frame(width: 14, height: 14)
                    .offset(x: -7)
                ForEach(0..<24, id: \.self) { _ in
                    Capsule().fill(.white.opacity(0.25)).frame(width: 8, height: 1)
                }
                Spacer()
                Circle().fill(Theme.Color.bg).frame(width: 14, height: 14)
                    .offset(x: 7)
            }
            .padding(.horizontal, 4)

            // Bottom half: redemption stub
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("REDEMPTION ID")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.55))
                    Text(response.redemptionId)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("PAID")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.55))
                    Text("\(response.costPoints) Sweat")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
            .padding(Theme.Space.lg)
        }
        .background(
            ZStack(alignment: .topTrailing) {
                LinearGradient(
                    colors: [
                        Color(red: 0.06, green: 0.06, blue: 0.07),
                        Color(red: 0.20, green: 0.04, blue: 0.06),
                        Color(red: 0.85, green: 0.02, blue: 0.16),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 220, height: 220)
                    .offset(x: 70, y: -90)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: Color(red: 0.85, green: 0.02, blue: 0.16).opacity(0.25),
                radius: 18, y: 8)
    }

    private func ticketField(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.55))
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private var receiptDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("On-chain receipt")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(Theme.Color.inkFaint)
                Spacer()
            }
            HStack {
                Text("0.001 SUI sent")
                    .font(.bodyM).foregroundStyle(Theme.Color.ink)
                Spacer()
                Text("operator → you")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.Color.inkSoft)
            }
            HStack {
                Text("Tx digest")
                    .font(.bodyM).foregroundStyle(Theme.Color.ink)
                Spacer()
                Text(shortDigest(response.txDigest))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.Color.inkSoft)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Theme.Color.bgElevated)
        )
    }

    private func shortDigest(_ d: String) -> String {
        guard d.count > 16 else { return d }
        return "\(d.prefix(8))…\(d.suffix(6))"
    }
}

#Preview {
    RewardsView()
        .environment(AppState())
}
