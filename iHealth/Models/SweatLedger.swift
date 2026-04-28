import Foundation

/// Local, append-only ledger of the user's Sweat economy. Tracks two
/// cumulative figures that aren't recoverable from the on-chain wallet
/// balance alone:
///
///   • `credited` — sum of `pointsMinted` returned by every server
///     mint. Includes bonuses (first-time, streak, multiplier) on top
///     of the raw workout points, so this is the "truth" for total
///     Sweat ever credited to the wallet.
///
///   • `redeemed` — sum of `costPoints` returned by every redemption
///     call (sample tickets, real drops). Truth for total Sweat ever
///     spent.
///
/// With the ledger we can render the Sweat breakdown without
/// guessing: bonus = credited − sum(workout.points minted on chain),
/// in-wallet = chain balance, redeemed = redeemed (truth).
struct SweatLedger: Codable, Equatable {
    var credited: Int
    var redeemed: Int

    static let zero = SweatLedger(credited: 0, redeemed: 0)
}
