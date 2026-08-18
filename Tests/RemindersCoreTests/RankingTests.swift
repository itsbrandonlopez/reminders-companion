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
/// replacement rank must be computed from the *new* neighbour values. Using the stale
/// ones drops the card at an arbitrary position.
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

    func testStaleNeighbourRanksWouldLandOutsideTheRespreadColumn() {
        // Two neighbours whose gap is exhausted.
        let staleAbove = 512.000000001
        let staleBelow = 512.000000002
        XCTAssertNil(Ranking.between(staleAbove, staleBelow))

        // After respreading to 0, 1024, 2048, reusing the stale pair would place the card
        // at ~512 — between the first and second slots regardless of where it was dropped.
        let respread = Ranking.normalized(count: 3)
        let fromStale = (staleAbove + staleBelow) / 2
        XCTAssertGreaterThan(fromStale, respread[0])
        XCTAssertLessThan(fromStale, respread[1])

        // Recomputed from the new values it lands where it should.
        let fromFresh = Ranking.between(respread[1], respread[2])
        XCTAssertEqual(fromFresh, 1536)
    }
}
