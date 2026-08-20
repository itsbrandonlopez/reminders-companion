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

    // MARK: - Sections

    func testSectionsAreScopedToTheirList() throws {
        let store = try makeStore()
        store.createSection(named: "Drafting", in: "list-a")
        store.createSection(named: "Review", in: "list-a")
        store.createSection(named: "Errands", in: "list-b")

        XCTAssertEqual(store.sections(in: "list-a").map(\.name), ["Drafting", "Review"],
                       "sections belong to one list and come back in creation order")
        XCTAssertEqual(store.sections(in: "list-b").map(\.name), ["Errands"])
        XCTAssertTrue(store.sections(in: "nonexistent").isEmpty)
    }

    func testReorderingSectionsSticks() throws {
        let store = try makeStore()
        store.createSection(named: "One", in: "l")
        store.createSection(named: "Two", in: "l")
        store.createSection(named: "Three", in: "l")

        var ordered = store.sections(in: "l")
        ordered.swapAt(0, 2)
        store.reorderSections(ordered)

        XCTAssertEqual(store.sections(in: "l").map(\.name), ["Three", "Two", "One"])
    }

    func testDeletingASectionRefilesItsTasksRatherThanLosingThem() throws {
        // The asymmetry the whole sidecar rests on: deleting an *arrangement* must never
        // take the arranged thing with it. These rows are the only copy of the estimate
        // and the manual position.
        let store = try makeStore()
        let section = store.createSection(named: "Doing", in: "l")
        store.ensure("task", title: "Real work", defaultRank: 10)
        store.setEstimate(45, for: "task")
        store.setSection(section.id.uuidString, for: "task")

        store.deleteSection(section)

        XCTAssertTrue(store.sections(in: "l").isEmpty)
        let row = store.meta(for: "task")
        XCTAssertNotNil(row, "the task's sidecar row must outlive its section")
        XCTAssertNil(row?.sectionID, "and come back unfiled rather than pointing at nothing")
        XCTAssertEqual(row?.estimateMinutes, 45)
        XCTAssertEqual(row?.rank, 10)
    }

    func testDeletingASectionClosesTheGapInTheOrder() throws {
        // Left alone, the next section created would take a sortIndex already in use and
        // sort ambiguously against its neighbour.
        let store = try makeStore()
        store.createSection(named: "One", in: "l")
        let middle = store.createSection(named: "Two", in: "l")
        store.createSection(named: "Three", in: "l")

        store.deleteSection(middle)
        store.createSection(named: "Four", in: "l")

        XCTAssertEqual(store.sections(in: "l").map(\.sortIndex), [0, 1, 2])
        XCTAssertEqual(store.sections(in: "l").map(\.name), ["One", "Three", "Four"])
    }

    func testSettingManySectionsAtOnce() throws {
        let store = try makeStore()
        let section = store.createSection(named: "Doing", in: "l")
        for id in ["a", "b", "c"] { store.ensure(id, title: id, defaultRank: 1) }
        store.setSection(section.id.uuidString, for: "c")

        store.setSections(["a": section.id.uuidString, "b": section.id.uuidString, "c": nil])

        XCTAssertEqual(store.meta(for: "a")?.sectionID, section.id.uuidString)
        XCTAssertEqual(store.meta(for: "b")?.sectionID, section.id.uuidString)
        XCTAssertNil(store.meta(for: "c")?.sectionID, "an explicit nil must unfile, not skip")
    }

    // MARK: - Duplicate rows

    // CloudKit does not support unique constraints, so `externalID` lost the one that used
    // to make a second row for a task impossible. Two devices working offline can now each
    // create one, and both arrive. These cover what replaces the constraint.

    /// Inserts a row without consulting what is already stored — which is exactly what a
    /// second device does, and what `ensure(_:title:defaultRank:in:)` does when handed an
    /// index that has not seen the existing row.
    private func insertRival(_ store: MetaStore, _ id: String, title: String, rank: Double) {
        var blindIndex: [String: TaskMeta] = [:]
        store.ensure(id, title: title, defaultRank: rank, in: &blindIndex)
        store.save()
    }

    func testDeduplicateCollapsesRivalRowsForOneTask() throws {
        let store = try makeStore()
        insertRival(store, "task", title: "From the Mac", rank: 1)
        insertRival(store, "task", title: "From the phone", rank: 2)
        XCTAssertEqual(store.all().count, 2, "precondition: the constraint really is gone")

        XCTAssertEqual(store.deduplicate(), 1)
        XCTAssertEqual(store.all().count, 1)
    }

    func testTheMoreRecentlySeenRowWins() throws {
        let store = try makeStore()
        insertRival(store, "task", title: "Stale", rank: 1)
        insertRival(store, "task", title: "Fresh", rank: 2)

        let rows = store.all().sorted { $0.rank < $1.rank }
        rows[0].lastSeen = .now.addingTimeInterval(-3600)
        rows[1].lastSeen = .now
        store.save()

        store.deduplicate()
        XCTAssertEqual(store.meta(for: "task")?.rank, 2, "the newer row's ordering is kept")
    }

    func testMergingKeepsValuesTheWinnerHasNoAnswerFor() throws {
        // The point of merging field by field rather than picking a row wholesale: an
        // estimate typed on one device must not be lost because the other device happened
        // to touch the task more recently.
        let store = try makeStore()
        insertRival(store, "task", title: "Older", rank: 1)
        insertRival(store, "task", title: "Newer", rank: 2)

        let rows = store.all().sorted { $0.rank < $1.rank }
        rows[0].lastSeen = .now.addingTimeInterval(-3600)
        rows[0].estimateMinutes = 90
        rows[0].sectionID = "section-uuid"
        rows[1].lastSeen = .now
        store.save()

        store.deduplicate()

        let survivor = store.meta(for: "task")
        XCTAssertEqual(survivor?.rank, 2, "the newer row is still the base")
        XCTAssertEqual(survivor?.estimateMinutes, 90, "but its blanks are filled from the other")
        XCTAssertEqual(survivor?.sectionID, "section-uuid")
    }

    func testTheRefreshPathCollapsesDuplicatesOnItsOwn() throws {
        // `indexedByExternalID` runs on every refresh and already walks every row, so it
        // is where duplicates are actually caught in practice.
        let store = try makeStore()
        insertRival(store, "task", title: "One", rank: 1)
        insertRival(store, "task", title: "Two", rank: 2)

        let index = store.indexedByExternalID()

        XCTAssertEqual(index.count, 1)
        XCTAssertEqual(store.all().count, 1, "and the loser is deleted, not just ignored")
    }

    func testDeduplicateLeavesDistinctTasksAlone() throws {
        let store = try makeStore()
        store.ensure("a", title: "A", defaultRank: 1)
        store.ensure("b", title: "B", defaultRank: 2)
        store.save()

        XCTAssertEqual(store.deduplicate(), 0)
        XCTAssertEqual(store.all().count, 2)
    }
}

