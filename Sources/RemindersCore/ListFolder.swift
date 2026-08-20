import Foundation
import SwiftData

/// A user-defined folder grouping Reminders lists.
///
/// Reminders supports folders, but **nothing exposes them**: EventKit has no group,
/// folder or parent concept at all, and Reminders' own AppleScript interface cannot even
/// see a list that lives inside a folder — `list "Projects"` errors with -1728 while
/// un-foldered lists resolve fine. So the hierarchy cannot be read, only recreated.
///
/// These folders therefore live in the sidecar and are configured once. Losing them costs
/// organisation, never data: every list and task still lives in Reminders untouched.
@Model
public final class ListFolder {
    // Defaults on every property and no unique constraint: both are CloudKit
    // requirements. The identifier is generated locally, so two devices cannot collide
    // on one the way they can on a task's external identifier.
    public var id: UUID = UUID()
    public var name: String = ""
    public var sortIndex: Int = 0
    /// `EKCalendar.calendarIdentifier` values, in display order.
    public var listIDs: [String] = []
    public var isCollapsed: Bool = false

    public init(
        id: UUID = UUID(),
        name: String,
        sortIndex: Int = 0,
        listIDs: [String] = [],
        isCollapsed: Bool = false
    ) {
        self.id = id
        self.name = name
        self.sortIndex = sortIndex
        self.listIDs = listIDs
        self.isCollapsed = isCollapsed
    }
}
