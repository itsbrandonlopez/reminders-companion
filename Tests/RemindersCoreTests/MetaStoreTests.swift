import XCTest
@testable import RemindersCore

/// The sidecar holds the only copy of manual ordering and estimates, so its collection
/// rule is the one place in the app that can lose user data outright.
@MainActor
final class MetaStoreTests: XCTestCase {

    private func makeStore() throws -> MetaStore { try MetaStore(inMemory: true) }

    func testEnsureCreatesThenReuses() throws {
        let store = try makeStore()
        let first = store.ensure("a", title: "Task", defaultRank: 100)
        XCTAssertEqual(first.rank, 100)

        // A second sighting must not reset the rank to the fallback.
        let second = store.ensure("a", title: "Task renamed", defaultRank: 999)
        XCTAssertEqual(second.rank, 100)
        XCTAssertEqual(second.titleSnapshot, "Task renamed")
        XCTAssertEqual(store.all().count, 1)
    }

    func testCompletingATaskDoesNotDeleteItsSidecarRow() throws {
        // The regression this guards: the app only ever fetches *incomplete* reminders,
        // so a completed task is absent from `livingIDs`. Collecting on absence would
        // throw away its estimate and manual position the moment it was ticked off.
        let store = try makeStore()
        store.ensure("done", title: "Ticked off", defaultRank: 5)
        store.setEstimate(120, for: "done")

        store.collectGarbage(livingIDs: [])

        XCTAssertEqual(store.meta(for: "done")?.estimateMinutes, 120,
                       "a task absent from the incomplete fetch must keep its metadata")
        XCTAssertEqual(store.meta(for: "done")?.rank, 5)
    }

    func testRowsAreCollectedOnceGenuinelyStale() throws {
        let store = try makeStore()
        store.ensure("gone", title: "Deleted elsewhere", defaultRank: 1)
        store.save()

        // Still fresh: nothing is collected.
        store.collectGarbage(livingIDs: [])
        XCTAssertNotNil(store.meta(for: "gone"))

        // Well past the staleness window, it goes.
        store.collectGarbage(livingIDs: [], now: .now.addingTimeInterval(MetaStore.staleAfter + 60))
        XCTAssertNil(store.meta(for: "gone"))
    }

    func testLivingRowsSurviveCollectionRegardlessOfAge() throws {
        let store = try makeStore()
        store.ensure("alive", title: "Still here", defaultRank: 1)
        store.collectGarbage(
            livingIDs: ["alive"], now: .now.addingTimeInterval(MetaStore.staleAfter * 10)
        )
        XCTAssertNotNil(store.meta(for: "alive"))
    }

    func testAssignMovesAListBetweenFoldersAndOutAgain() throws {
        let store = try makeStore()
        let work = store.createFolder(named: "Work")
        let personal = store.createFolder(named: "Personal")

        store.assign(listID: "L1", to: work)
        XCTAssertEqual(work.listIDs, ["L1"])

        // A list belongs to at most one folder, as in Reminders.
        store.assign(listID: "L1", to: personal)
        XCTAssertTrue(work.listIDs.isEmpty)
        XCTAssertEqual(personal.listIDs, ["L1"])

        store.assign(listID: "L1", to: nil)
        XCTAssertTrue(personal.listIDs.isEmpty)
    }

    func testAssigningTwiceDoesNotDuplicate() throws {
        let store = try makeStore()
        let work = store.createFolder(named: "Work")
        store.assign(listID: "L1", to: work)
        store.assign(listID: "L1", to: work)
        XCTAssertEqual(work.listIDs, ["L1"])
    }

    func testDeletingAFolderLeavesNoTraceOfItsLists() throws {
        let store = try makeStore()
        let work = store.createFolder(named: "Work")
        store.assign(listID: "L1", to: work)
        store.deleteFolder(work)
        XCTAssertTrue(store.folders().isEmpty)
    }
}
