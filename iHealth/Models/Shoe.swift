import Foundation

/// A shoe the athlete uses to log mileage. Logged shoes nudge for
/// replacement around 500km — the same "gear mortality ledger" NRC made
/// famous. In the on-chain version each shoe is an NFT whose mileage ticks
/// up with each verified workout tagged to it.
struct Shoe: Identifiable, Hashable {
    var id: UUID
    var brand: String                       // "Nike", "Hoka", "Saucony"
    var model: String                       // "Vaporfly 3"
    var nickname: String?                   // "Long run shoes"
    var tone: AvatarTone
    var milesUsed: Double                   // km in practice; we display both
    var milesTotal: Double                  // expected life
    var retired: Bool
    var startedAt: Date

    var fraction: Double {
        guard milesTotal > 0 else { return 0 }
        return min(1.0, milesUsed / milesTotal)
    }

    var isTired: Bool { fraction >= 0.85 && !retired }
}
