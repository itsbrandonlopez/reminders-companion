import Foundation

/// Fractional indexing for manual ordering.
///
/// Reminders has no sort-order field of any kind, so column position lives in our own
/// sidecar. Fractional ranks mean a drag writes exactly one sidecar row instead of
/// renumbering everything below it.
public enum Ranking {

    public static let step: Double = 1024

    /// Doubles run out of room after roughly 50 consecutive drops into the same gap.
    /// Below this the gap is treated as exhausted and the column is renumbered.
    static let minimumGap: Double = 1e-9

    /// A rank that sorts between `above` and `below`. Pass nil for an open end.
    /// Returns nil when the gap is too small to subdivide — the caller should call
    /// `normalized(_:)` and retry.
    public static func between(_ above: Double?, _ below: Double?) -> Double? {
        switch (above, below) {
        case (nil, nil):
            return 0
        case let (nil, .some(b)):
            return b - step
        case let (.some(a), nil):
            return a + step
        case let (.some(a), .some(b)):
            let (lo, hi) = a <= b ? (a, b) : (b, a)
            guard hi - lo > minimumGap else { return nil }
            return lo + (hi - lo) / 2
        }
    }

    /// Evenly spaced ranks for a column, used to seed new items and to recover when
    /// `between` reports an exhausted gap.
    public static func normalized(count: Int) -> [Double] {
        (0..<count).map { Double($0) * step }
    }

    /// Renumbers an exhausted column and reports where the drop target's neighbours ended
    /// up.
    ///
    /// This is the half of the recovery path that is easy to get wrong. Once the column has
    /// been respread, the *old* neighbour ranks describe positions that no longer exist —
    /// subdividing between them lands the card at an arbitrary point near the top rather
    /// than where it was dropped. The replacement rank has to come from the new values, so
    /// this returns them alongside the renumbering rather than leaving the caller to look
    /// them up again.
    ///
    /// Pure, and separate from `ReminderStore.reorder`, so the rule can be tested without a
    /// sidecar or an EventKit store behind it.
    ///
    /// - Parameters:
    ///   - column: every id in the column the drop happened in, already in display order.
    ///   - above: the id the card was dropped below, if any.
    ///   - below: the id the card was dropped above, if any.
    /// - Returns: the new rank for every id, plus the post-respread ranks of the two
    ///   neighbours — ready to hand straight to `between`.
    public static func respread(
        _ column: [String], above: String?, below: String?
    ) -> (ranks: [String: Double], above: Double?, below: Double?) {
        var ranks: [String: Double] = [:]
        ranks.reserveCapacity(column.count)
        for (id, rank) in zip(column, normalized(count: column.count)) {
            ranks[id] = rank
        }
        return (ranks, above.flatMap { ranks[$0] }, below.flatMap { ranks[$0] })
    }
}
