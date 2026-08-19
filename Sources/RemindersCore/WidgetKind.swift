import Foundation

/// Widget kind identifiers, shared between the widget extension (which registers them)
/// and the main app (which reloads them after a mutation). One source of truth so a typo
/// in one place can't silently turn a reload into a no-op.
public enum WidgetKind {
    public static let today = "TodayWidget"
    public static let nextUp = "NextUpWidget"
    /// The watch-face complication. Registered by the watchOS widget extension and
    /// reloaded by the watch app and the iPhone-side Watch bridge.
    public static let watchToday = "WatchTodayComplication"
}
