import XCTest
@testable import RemindersCore

/// The Watch and the iPhone agree on a dictionary sent across a process and a device
/// boundary, where a typo becomes a silently ignored completion rather than a compile
/// error. These pin the contract from both ends.
///
/// They call `WatchRequest` directly. An earlier version of this file re-declared the keys
/// and re-implemented `parse`, on the grounds that the type lived in an iOS/watchOS-only
/// module — which meant it was testing a hand-copied duplicate. Renaming
/// `WatchRequest.completeAction`, swapping two keys, or tightening `parse` left all of
/// these passing while the Watch quietly stopped being able to complete anything. The type
/// now lives in `RemindersCore` precisely so this file can reach it.
final class WatchRequestTests: XCTestCase {

    private func decode(_ payload: [String: Any]) -> String? {
        WatchRequest.parse(payload)?.taskID
    }

    func testRoundTrip() {
        let id = "ABC-123-EXTERNAL"
        XCTAssertEqual(decode(WatchRequest.complete(taskID: id)), id)
    }

    /// The wire keys themselves. A build of the watch app and a build of the phone app can
    /// ship weeks apart, so these strings are the compatibility surface — changing one is a
    /// breaking change and should read as one here.
    func testWireFormatIsExactlyWhatBothSidesExpect() {
        let payload = WatchRequest.complete(taskID: "t-1", requestID: "r-1")
        XCTAssertEqual(payload["action"] as? String, "complete")
        XCTAssertEqual(payload["taskID"] as? String, "t-1")
        XCTAssertEqual(payload["requestID"] as? String, "r-1")
        XCTAssertEqual(payload.count, 3, "an unexpected extra key means the shape drifted")
    }

    func testRejectsUnknownAction() {
        // A future action must not be misread as a completion by an older build on the
        // other device — the two can be updated independently.
        XCTAssertNil(decode([WatchRequest.actionKey: "reschedule", WatchRequest.taskIDKey: "abc"]))
    }

    func testRejectsMalformedPayloads() {
        XCTAssertNil(decode([:]))
        XCTAssertNil(decode([WatchRequest.actionKey: WatchRequest.completeAction]))
        XCTAssertNil(decode([WatchRequest.taskIDKey: "abc"]))
        XCTAssertNil(decode([
            WatchRequest.actionKey: WatchRequest.completeAction, WatchRequest.taskIDKey: "",
        ]))
        XCTAssertNil(decode([WatchRequest.actionKey: 42, WatchRequest.taskIDKey: "abc"]))
        XCTAssertNil(decode([
            WatchRequest.actionKey: WatchRequest.completeAction, WatchRequest.taskIDKey: 42,
        ]))
    }

    /// A retried send must carry the same request id, which is what lets the phone
    /// recognise a duplicate rather than performing the action twice.
    func testRequestIDSurvivesTheRoundTrip() {
        let payload = WatchRequest.complete(taskID: "t", requestID: "abc")
        XCTAssertEqual(WatchRequest.parse(payload)?.requestID, "abc")
    }

    /// Two sends of the same completion are distinguishable from one send retried.
    func testEachRequestGetsItsOwnIDByDefault() {
        let first = WatchRequest.complete(taskID: "t")
        let second = WatchRequest.complete(taskID: "t")
        XCTAssertNotEqual(
            WatchRequest.parse(first)?.requestID,
            WatchRequest.parse(second)?.requestID
        )
    }

    /// An older watch build predates the request id; it must still work, falling back to
    /// the task id so repeats of the same completion are at least still deduped.
    func testMissingRequestIDFallsBackToTheTaskID() {
        let legacy: [String: Any] = [
            WatchRequest.actionKey: WatchRequest.completeAction,
            WatchRequest.taskIDKey: "task-9",
        ]
        XCTAssertEqual(WatchRequest.parse(legacy)?.requestID, "task-9")

        let blank: [String: Any] = [
            WatchRequest.actionKey: WatchRequest.completeAction,
            WatchRequest.taskIDKey: "task-9",
            WatchRequest.requestIDKey: "",
        ]
        XCTAssertEqual(WatchRequest.parse(blank)?.requestID, "task-9")
    }

    /// Identifiers are `calendarItemExternalIdentifier` values, which are UUID-shaped but
    /// treated as opaque — nothing about the payload should assume a format.
    func testTreatsIdentifiersAsOpaque() {
        for id in ["x", "with spaces", "ünïcodé", String(repeating: "9", count: 300)] {
            XCTAssertEqual(decode(WatchRequest.complete(taskID: id)), id, "failed for \(id.prefix(20))")
        }
    }
}
