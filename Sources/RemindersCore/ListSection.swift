import Foundation
import SwiftData

/// A user-defined section within one Reminders list — the thing Reminders itself calls a
/// section, and shows as a column in its Kanban view.
///
/// Recreated here rather than mirrored, because **nothing exposes them**. Verified against
/// the macOS 26.5 SDK: the string "section" does not appear anywhere in EventKit's headers,
/// `EKReminder` adds only start, due, completed, completionDate and priority over
/// `EKCalendarItem`, and Reminders' own AppleScript dictionary declares exactly three
/// classes — account, list, reminder — with no section among them. The private store under
/// `~/Library/Group Containers/group.com.apple.reminders` is TCC-protected, and building on
/// an undocumented schema that Apple can restructure in a point release would trade this
/// app's one real guarantee for a feature.
///
/// So sections are typed once, here, and matched to the ones in Reminders by name and by
/// eye. Same bargain as [ListFolder]: losing the sidecar costs the arrangement, never a
/// task. And like folders, they are Mac-only — the phone shows a list's tasks flat.
@Model
public final class ListSection {
    // Defaults and no unique constraint, as CloudKit requires. Creating "Doing" on two
    // devices before they sync makes two genuinely different sections rather than a
    // conflict, since each carries its own locally generated identifier — they arrive as
    // two columns for you to merge by hand, which is the honest outcome.
    public var id: UUID = UUID()
    /// `EKCalendar.calendarIdentifier` — the list this section belongs to. Sections do not
    /// span lists, matching Reminders.
    public var listID: String = ""
    public var name: String = ""
    public var sortIndex: Int = 0

    public init(id: UUID = UUID(), listID: String, name: String, sortIndex: Int = 0) {
        self.id = id
        self.listID = listID
        self.name = name
        self.sortIndex = sortIndex
    }
}
