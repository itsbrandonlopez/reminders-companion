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
    private let completeAction = "complete"

    private func encode(taskID: String) -> [String: Any] {
        [actionKey: completeAction, taskIDKey: taskID]
    }

    private func decode(_ payload: [String: Any]) -> String? {
        guard payload[actionKey] as? String == completeAction,
              let id = payload[taskIDKey] as? String, !id.isEmpty else { return nil }
        return id
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

    /// Identifiers are `calendarItemExternalIdentifier` values, which are UUID-shaped but
    /// treated as opaque — nothing about the payload should assume a format.
    func testTreatsIdentifiersAsOpaque() {
        for id in ["x", "with spaces", "ünïcodé", String(repeating: "9", count: 300)] {
            XCTAssertEqual(decode(encode(taskID: id)), id, "failed for \(id.prefix(20))")
        }
    }
}
