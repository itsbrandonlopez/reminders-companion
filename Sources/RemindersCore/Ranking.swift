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
}
