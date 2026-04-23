import Foundation

/// Streak state. Crypto-native twist: users can STAKE $SWEAT against their
/// streak — if the streak breaks, the stake burns / goes to community pot;
/// if the streak holds through a milestone, multiplier kicks in.
struct Streak: Hashable {
    var currentDays: Int
    var longestDays: Int
    var weeklyStreakWeeks: Int       // NRC-style weekly streak (at least 1 run per calendar week)
    var atRiskByDate: Date?          // nil = safe; otherwise deadline to avoid break
    var stakedSweat: Int             // 0 if no stake active
    var stakeExpiresAt: Date?        // when stake cycle ends
    var multiplier: Double           // 1.0 base, grows with consistency

    var isAtRisk: Bool {
        guard let deadline = atRiskByDate else { return false }
        return deadline > Date() && deadline.timeIntervalSinceNow < 12 * 3600
    }

    /// Hours remaining until the streak would break.
    var hoursUntilAtRisk: Int? {
        guard let deadline = atRiskByDate else { return nil }
        let secs = Int(deadline.timeIntervalSinceNow)
        return max(0, secs / 3600)
    }
}
