#if os(iOS) || os(watchOS)
import Foundation
import RemindersCore
import WatchConnectivity

/// Carries a write request from the Watch to the iPhone.
///
/// watchOS EventKit is read-only, so the Watch can never complete a task itself. It asks
/// the phone to, and the phone runs the same `ReminderStore.completeReminder` the widget's
/// intent uses — one completion path shared by every surface rather than several that
/// drift apart.
public enum WatchRequest {
    public static let actionKey = "action"
    public static let taskIDKey = "taskID"
    public static let completeAction = "complete"

    public static func complete(taskID: String) -> [String: Any] {
        [actionKey: completeAction, taskIDKey: taskID]
    }

    /// Returns the task id when the payload is a well-formed completion request.
    public static func taskID(from payload: [String: Any]) -> String? {
        guard payload[actionKey] as? String == completeAction,
              let id = payload[taskIDKey] as? String, !id.isEmpty else { return nil }
        return id
    }
}

/// Thin wrapper over `WCSession`, activated once per process.
///
/// `WCSessionDelegate` is an Objective-C protocol with required callbacks that differ by
/// platform, which is why this is a class rather than a struct and why the iOS-only
/// callbacks are conditionally compiled.
public final class WatchBridge: NSObject, @unchecked Sendable {
    public static let shared = WatchBridge()

    /// Called on the receiving side (the iPhone) with an incoming task id.
    public var onCompleteRequest: (@Sendable (String) -> Void)?

    private override init() { super.init() }

    public func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    #if os(watchOS)
    /// Sends a completion to the phone.
    ///
    /// `sendMessage` is immediate but requires the phone to be reachable. When it is not —
    /// phone left at home, or simply asleep — `transferUserInfo` queues the request and
    /// iOS delivers it, in order, once the two reconnect. Without the fallback, completing
    /// a task on a run would silently do nothing.
    public func requestComplete(taskID: String) {
        let payload = WatchRequest.complete(taskID: taskID)
        let session = WCSession.default
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in
                // Reachability can lapse between the check and the send, so a failed
                // immediate message still falls back to the queue rather than vanishing.
                session.transferUserInfo(payload)
            }
        } else {
            session.transferUserInfo(payload)
        }
    }
    #endif
}

extension WatchBridge: WCSessionDelegate {
    public func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    /// Immediate path, when both devices are awake and in range.
    public func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if let id = WatchRequest.taskID(from: message) { onCompleteRequest?(id) }
    }

    /// Queued path. iOS wakes the app in the background to deliver these, which is what
    /// makes a completion tapped hours earlier still land.
    public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        if let id = WatchRequest.taskID(from: userInfo) { onCompleteRequest?(id) }
    }

    #if os(iOS)
    // Required on iOS only, and only relevant when switching between paired watches.
    public func sessionDidBecomeInactive(_ session: WCSession) {}
    public func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate so a newly paired watch can still reach us.
        WCSession.default.activate()
    }
    #endif
}
#endif
