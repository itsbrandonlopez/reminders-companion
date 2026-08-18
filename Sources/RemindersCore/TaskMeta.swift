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
@Model
public final class TaskMeta {
    @Attribute(.unique) public var externalID: String
    public var rank: Double
    public var estimateMinutes: Int?
    /// Kept only so an orphaned row is recognisable when debugging; never authoritative.
    public var titleSnapshot: String
    /// Refreshed on every sync so rows for deleted reminders can be collected.
    public var lastSeen: Date

    public init(
        externalID: String,
        rank: Double = 0,
        estimateMinutes: Int? = nil,
        titleSnapshot: String = "",
        lastSeen: Date = .now
    ) {
        self.externalID = externalID
        self.rank = rank
        self.estimateMinutes = estimateMinutes
        self.titleSnapshot = titleSnapshot
        self.lastSeen = lastSeen
    }
}
