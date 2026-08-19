#if os(iOS) || os(watchOS)
import Foundation
import RemindersCore
import WatchConnectivity

// `WatchRequest` — the payload contract itself — now lives in `RemindersCore`. It is pure
// Foundation; this file's `#if os(iOS) || os(watchOS)` exists for `WCSession`, not for it,
// and keeping it here meant the unit tests could not import it and tested a hand-copied
// duplicate instead.
/// Thin wrapper over `WCSession`, activated once per process.
///
/// `WCSessionDelegate` is an Objective-C protocol with required callbacks that differ by
/// platform, which is why this is a class rather than a struct and why the iOS-only
/// callbacks are conditionally compiled.
public final class WatchBridge: NSObject, @unchecked Sendable {
    public static let shared = WatchBridge()

    /// Called on the receiving side (the iPhone) with an incoming task id.
    public var onCompleteRequest: (@Sendable (String) -> Void)?

    /// Requests that arrived before a handler was installed.
    ///
    /// iOS delivers a queued `transferUserInfo` by launching the app in the background,
    /// where the SwiftUI scene may never appear. Buffering means a completion tapped on a
    /// run still lands once the app finishes waking, instead of being dropped because the
    /// handler was not attached yet.
    private var buffered: [String] = []
    private var handledRequestIDs: Set<String> = []
    private let lock = NSLock()

    private override init() { super.init() }

    public func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        // Assigning an already-set delegate is harmless; activating twice is a no-op.
        session.delegate = self
        if session.activationState != .activated { session.activate() }
    }

    /// Installs the handler and drains anything that arrived before it existed.
    public func setCompleteHandler(_ handler: @escaping @Sendable (String) -> Void) {
        lock.lock()
        onCompleteRequest = handler
        let pending = buffered
        buffered.removeAll()
        lock.unlock()
        pending.forEach(handler)
    }

    /// Runs the handler, or buffers the id until one is installed. Ignores a request id
    /// already seen, so a retried send cannot act twice.
    fileprivate func deliver(taskID: String, requestID: String) {
        lock.lock()
        guard !handledRequestIDs.contains(requestID) else { lock.unlock(); return }
        handledRequestIDs.insert(requestID)
        // Unbounded growth would be a slow leak in a long-lived app; the window only needs
        // to outlast a retry.
        if handledRequestIDs.count > 200 { handledRequestIDs.removeAll() }
        let handler = onCompleteRequest
        if handler == nil { buffered.append(taskID) }
        lock.unlock()
        handler?(taskID)
    }

    #if os(watchOS)
    /// Sends a completion to the phone.
    ///
    /// `sendMessage` is immediate but requires the phone to be reachable. When it is not —
    /// phone left at home, or simply asleep — `transferUserInfo` queues the request and
    /// iOS delivers it, in order, once the two reconnect. Without the fallback, completing
    /// a task on a run would silently do nothing.
    public func requestComplete(taskID: String) {
        // One id for both attempts: the whole point is that the phone can recognise the
        // retry as the same request.
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
        if let r = WatchRequest.parse(message) { deliver(taskID: r.taskID, requestID: r.requestID) }
    }

    /// Queued path. iOS wakes the app in the background to deliver these, which is what
    /// makes a completion tapped hours earlier still land.
    public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        if let r = WatchRequest.parse(userInfo) { deliver(taskID: r.taskID, requestID: r.requestID) }
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
