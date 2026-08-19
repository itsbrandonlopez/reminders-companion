import XCTest
@testable import RemindersCore

final class RankingTests: XCTestCase {

    func testFirstItemInEmptyColumn() {
        XCTAssertEqual(Ranking.between(nil, nil), 0)
    }

    func testDropAtTopAndBottom() {
        XCTAssertEqual(Ranking.between(nil, 100), 100 - Ranking.step)
        XCTAssertEqual(Ranking.between(100, nil), 100 + Ranking.step)
    }

    func testDropBetweenTwoItems() {
        XCTAssertEqual(Ranking.between(0, 1024), 512)
    }

    func testHandlesReversedNeighbours() {
        XCTAssertEqual(Ranking.between(1024, 0), 512)
    }

    func testRepeatedSubdivisionStaysStrictlyOrdered() {
        // The property that matters: a rank always sorts strictly between its neighbours.
        var lower = 0.0
        let upper = Ranking.step
        for _ in 0..<40 {
            guard let mid = Ranking.between(lower, upper) else { break }
            XCTAssertGreaterThan(mid, lower)
            XCTAssertLessThan(mid, upper)
            lower = mid
        }
    }

    func testExhaustedGapReportsNilSoCallerCanRenumber() {
        XCTAssertNil(Ranking.between(1.0, 1.0))
        XCTAssertNil(Ranking.between(1.0, 1.0 + 1e-12))
    }

    func testNormalizedIsEvenlySpacedAndAscending() {
        let ranks = Ranking.normalized(count: 4)
        XCTAssertEqual(ranks, [0, 1024, 2048, 3072])
        XCTAssertEqual(ranks, ranks.sorted())
        XCTAssertEqual(Ranking.normalized(count: 0), [])
    }
}

/// Guards the respread path: when a gap is exhausted the column is renumbered, and the
/// replacement rank must be computed from the *new* neighbour values. Using the stale ones
/// drops the card at an arbitrary position.
///
/// These call `Ranking.respread`, which is the code the drop actually runs. The previous
/// version of this suite asserted hand-computed float arithmetic — `(staleAbove +
/// staleBelow) / 2` — which is a fact about two literals and held no matter what the
/// respread path did. Inverting the fresh/stale choice left it green.
final class RankingRespreadTests: XCTestCase {

    func testRespreadProducesUsableGapsBetweenEveryNeighbour() {
        let ranks = Ranking.normalized(count: 5)
        for pair in zip(ranks, ranks.dropFirst()) {
            let mid = Ranking.between(pair.0, pair.1)
            XCTAssertNotNil(mid, "a freshly respread column must always be subdividable")
            XCTAssertGreaterThan(mid!, pair.0)
            XCTAssertLessThan(mid!, pair.1)
        }
    }

    func testRespreadRenumbersTheWholeColumnInOrder() {
        let result = Ranking.respread(["a", "b", "c", "d"], above: nil, below: nil)
        XCTAssertEqual(result.ranks["a"], 0)
        XCTAssertEqual(result.ranks["b"], Ranking.step)
        XCTAssertEqual(result.ranks["c"], Ranking.step * 2)
        XCTAssertEqual(result.ranks["d"], Ranking.step * 3)
        XCTAssertNil(result.above)
        XCTAssertNil(result.below)
    }

    /// The whole point of the function: the neighbours it reports are the *post*-respread
    /// values, so the caller subdivides the gap that now exists rather than one that used
    /// to.
    func testReportedNeighboursAreThePostRespreadValues() {
        // A column whose gap between c and d is exhausted, and a drop aimed at that gap.
        let column = ["a", "b", "c", "d"]
        let result = Ranking.respread(column, above: "c", below: "d")

        XCTAssertEqual(result.above, Ranking.step * 2)
        XCTAssertEqual(result.below, Ranking.step * 3)

        let placed = Ranking.between(result.above, result.below)
        XCTAssertNotNil(placed, "the respread column must leave a subdividable gap")

        // The card lands strictly between c and d, and nowhere else.
        let ordered = (result.ranks.merging(["dropped": placed!]) { a, _ in a })
            .sorted { $0.value < $1.value }
            .map(\.key)
        XCTAssertEqual(ordered, ["a", "b", "c", "dropped", "d"])
    }

    /// The failure the fresh-neighbour rule prevents, stated as an ordering rather than as
    /// arithmetic: reusing the exhausted pre-respread ranks puts the card near the top of
    /// the column no matter where it was aimed.
    func testReusingStaleNeighboursWouldMisplaceTheCard() {
        let column = ["a", "b", "c", "d"]
        // c and d had collapsed onto each other after many drops into the same slot.
        let staleAbove = 512.000000001
        let staleBelow = 512.000000002
        XCTAssertNil(Ranking.between(staleAbove, staleBelow), "precondition: the gap is exhausted")

        let result = Ranking.respread(column, above: "c", below: "d")
        let fromStale = (staleAbove + staleBelow) / 2

        let misplaced = (result.ranks.merging(["dropped": fromStale]) { a, _ in a })
            .sorted { $0.value < $1.value }
            .map(\.key)
        XCTAssertEqual(
            misplaced, ["a", "dropped", "b", "c", "d"],
            "stale ranks land the card between the first and second slots, not where it was dropped"
        )
    }

    func testRespreadHandlesAnOpenEnd() {
        let result = Ranking.respread(["a", "b"], above: "b", below: nil)
        XCTAssertEqual(result.above, Ranking.step)
        XCTAssertNil(result.below)
        XCTAssertEqual(Ranking.between(result.above, result.below), Ranking.step * 2)
    }

    /// A neighbour that has since left the column reports nil rather than a stale value.
    func testNeighbourMissingFromTheColumnIsReportedAsAnOpenEnd() {
        let result = Ranking.respread(["a", "b"], above: "vanished", below: "b")
        XCTAssertNil(result.above)
        XCTAssertEqual(result.below, Ranking.step)
    }

    func testEmptyColumn() {
        let result = Ranking.respread([], above: "a", below: "b")
        XCTAssertTrue(result.ranks.isEmpty)
        XCTAssertNil(result.above)
        XCTAssertNil(result.below)
    }
}
