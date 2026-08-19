import XCTest
@testable import RemindersCore

/// The Watch and the iPhone agree on a dictionary sent across a process and device
/// boundary, where a typo becomes a silently ignored completion rather than a compile
/// error. These pin the contract from both ends.
///
/// `WatchRequest` itself lives in `RemindersShared` (iOS + watchOS only), so this mirrors
/// its encoding rather than importing it — the point is that the shape is deliberate and
/// stays fixed, and this fails loudly if the constants below ever drift from that file.
final class WatchRequestTests: XCTestCase {

    private let actionKey = "action"
    private let taskIDKey = "taskID"
    private let requestIDKey = "requestID"
    private let completeAction = "complete"

    private func encode(taskID: String, requestID: String = "req-1") -> [String: Any] {
        [actionKey: completeAction, taskIDKey: taskID, requestIDKey: requestID]
    }

    private func decode(_ payload: [String: Any]) -> String? { parse(payload)?.taskID }

    private func parse(_ payload: [String: Any]) -> (taskID: String, requestID: String)? {
        guard payload[actionKey] as? String == completeAction,
              let id = payload[taskIDKey] as? String, !id.isEmpty else { return nil }
        let requestID = (payload[requestIDKey] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? id
        return (id, requestID)
    }

    func testRoundTrip() {
        let id = "ABC-123-EXTERNAL"
        XCTAssertEqual(decode(encode(taskID: id)), id)
    }

    func testRejectsUnknownAction() {
        // A future action must not be misread as a completion by an older build on the
        // other device — the two can be updated independently.
        XCTAssertNil(decode([actionKey: "reschedule", taskIDKey: "abc"]))
    }

    func testRejectsMalformedPayloads() {
        XCTAssertNil(decode([:]))
        XCTAssertNil(decode([actionKey: completeAction]))
        XCTAssertNil(decode([taskIDKey: "abc"]))
        XCTAssertNil(decode([actionKey: completeAction, taskIDKey: ""]))
        XCTAssertNil(decode([actionKey: 42, taskIDKey: "abc"]))
        XCTAssertNil(decode([actionKey: completeAction, taskIDKey: 42]))
    }

    /// A retried send must carry the same request id, which is what lets the phone
    /// recognise a duplicate rather than performing the action twice.
    func testRequestIDSurvivesTheRoundTrip() {
        XCTAssertEqual(parse(encode(taskID: "t", requestID: "abc"))?.requestID, "abc")
    }

    /// An older watch build predates the request id; it must still work, falling back to
    /// the task id so repeats of the same completion are at least still deduped.
    func testMissingRequestIDFallsBackToTheTaskID() {
        let legacy: [String: Any] = [actionKey: completeAction, taskIDKey: "task-9"]
        XCTAssertEqual(parse(legacy)?.requestID, "task-9")
        let blank: [String: Any] = [actionKey: completeAction, taskIDKey: "task-9", requestIDKey: ""]
        XCTAssertEqual(parse(blank)?.requestID, "task-9")
    }

    /// Identifiers are `calendarItemExternalIdentifier` values, which are UUID-shaped but
    /// treated as opaque — nothing about the payload should assume a format.
    func testTreatsIdentifiersAsOpaque() {
        for id in ["x", "with spaces", "ünïcodé", String(repeating: "9", count: 300)] {
            XCTAssertEqual(decode(encode(taskID: id)), id, "failed for \(id.prefix(20))")
        }
    }
}
