import Foundation
import SwiftData

/// Sidecar row for the things Reminders has nowhere to put.
///
/// EventKit exposes no ordering field, no estimates, and no custom metadata of any kind
/// (subtasks, tags and flags are likewise absent from the API — see spike/FINDINGS.md),
/// so anything beyond the native fields lives here.
///
/// Keyed on `calendarItemExternalIdentifier`: the header documents `calendarItemIdentifier`
/// as *not* sync-proof, so it is deliberately never persisted.
/// **CloudKit constraints shape this type.** Every stored property carries a default and
/// none is uniquely constrained, because CloudKit supports neither. `externalID` was
/// `@Attribute(.unique)` when the sidecar was local-only, and that constraint was what
/// stopped a second row appearing for the same task. Across devices it is `deduplicate`'s
/// job instead — two Macs offline can each create a row for the same reminder, and only a
/// merge after the fact can reconcile them.
@Model
public final class TaskMeta {
    public var externalID: String = ""
    public var rank: Double = 0
    public var estimateMinutes: Int?
    /// The `ListSection` this task sits in, as a UUID string, or nil for the list's
    /// unsectioned column. Stored flat rather than as a SwiftData relationship so a
    /// deleted section leaves a dangling id that reads as "unsectioned" instead of
    /// cascading into the task's row.
    public var sectionID: String?
    /// Kept only so an orphaned row is recognisable when debugging; never authoritative.
    public var titleSnapshot: String = ""
    /// Refreshed on every sync so rows for deleted reminders can be collected. Doubles as
    /// the tiebreak when two devices' rows for one task have to be merged.
    public var lastSeen: Date = Date.distantPast

    public init(
        externalID: String,
        rank: Double = 0,
        estimateMinutes: Int? = nil,
        sectionID: String? = nil,
        titleSnapshot: String = "",
        lastSeen: Date = .now
    ) {
        self.externalID = externalID
        self.rank = rank
        self.estimateMinutes = estimateMinutes
        self.sectionID = sectionID
        self.titleSnapshot = titleSnapshot
        self.lastSeen = lastSeen
    }
}
