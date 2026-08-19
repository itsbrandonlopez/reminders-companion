import Foundation
import SwiftData

/// Owns the sidecar database and keeps it reconciled against what Reminders reports.
///
/// Local-only by design: if this file is lost, every task, list and date is still intact
/// in Reminders — only manual ordering and estimates go with it. That asymmetry is
/// deliberate, and it is why the sidecar never holds anything Reminders could have held.
@MainActor
public final class MetaStore {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    public init(inMemory: Bool = false) throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        container = try ModelContainer(for: TaskMeta.self, ListFolder.self, configurations: config)
    }

    public func meta(for externalID: String) -> TaskMeta? {
        let descriptor = FetchDescriptor<TaskMeta>(
            predicate: #Predicate { $0.externalID == externalID }
        )
        return try? context.fetch(descriptor).first
    }

    @discardableResult
    public func ensure(_ externalID: String, title: String, defaultRank: @autoclosure () -> Double) -> TaskMeta {
        if let existing = meta(for: externalID) {
            existing.titleSnapshot = title
            existing.lastSeen = .now
            return existing
        }
        let created = TaskMeta(externalID: externalID, rank: defaultRank(), titleSnapshot: title)
        context.insert(created)
        return created
    }

    public func all() -> [TaskMeta] {
        (try? context.fetch(FetchDescriptor<TaskMeta>())) ?? []
    }

    /// Every row, indexed by external identifier.
    ///
    /// `meta(for:)` compiles and runs a predicate fetch per call, so reconciling a refresh
    /// of *n* reminders one at a time was *n* round trips into SwiftData — invisible at 50
    /// reminders, the dominant cost at 10,000. Anything touching many tasks takes the whole
    /// table once instead. The rows are small, and the caller is already holding every
    /// matching `EKReminder` in memory at that moment anyway.
    public func indexedByExternalID() -> [String: TaskMeta] {
        var index: [String: TaskMeta] = [:]
        let rows = all()
        index.reserveCapacity(rows.count)
        for row in rows { index[row.externalID] = row }
        return index
    }

    /// `ensure`, against a caller-held index rather than a fresh fetch.
    ///
    /// Inserts into `index` as well as the context, so a bulk pass stays consistent without
    /// going back to the database for rows it just created.
    @discardableResult
    public func ensure(
        _ externalID: String,
        title: String,
        defaultRank: @autoclosure () -> Double,
        in index: inout [String: TaskMeta]
    ) -> TaskMeta {
        if let existing = index[externalID] {
            existing.titleSnapshot = title
            existing.lastSeen = .now
            return existing
        }
        let created = TaskMeta(externalID: externalID, rank: defaultRank(), titleSnapshot: title)
        context.insert(created)
        index[externalID] = created
        return created
    }

    public func setRank(_ rank: Double, for externalID: String) {
        meta(for: externalID)?.rank = rank
        save()
    }

    /// Applies many ranks in a single transaction.
    ///
    /// A column respread calls this once instead of `setRank` per card, which was a fetch
    /// *and* a `context.save()` each — 200 of both for a 200-card column.
    public func setRanks(_ ranks: [String: Double]) {
        guard !ranks.isEmpty else { return }
        let index = indexedByExternalID()
        for (externalID, rank) in ranks {
            index[externalID]?.rank = rank
        }
        save()
    }

    public func setEstimate(_ minutes: Int?, for externalID: String) {
        meta(for: externalID)?.estimateMinutes = minutes
        save()
    }

    /// How long a row survives after its task was last seen in the incomplete fetch.
    public static let staleAfter: TimeInterval = 60 * 60 * 24 * 30

    /// Drops rows for tasks that have been gone a long time.
    ///
    /// Deliberately *not* "anything missing from this refresh": the only fetch the app
    /// makes is `predicateForIncompleteReminders`, so a task you simply ticked off is
    /// absent too. Deleting on absence would throw away its estimate and manual position
    /// the moment it was completed, and lose them for good if you later un-ticked it.
    /// Waiting for genuine staleness keeps completed work recoverable while still
    /// clearing rows for tasks deleted on another device.
    public func collectGarbage(livingIDs: Set<String>, now: Date = .now) {
        let cutoff = now.addingTimeInterval(-Self.staleAfter)
        var removed = 0
        for meta in all() where !livingIDs.contains(meta.externalID) && meta.lastSeen < cutoff {
            context.delete(meta)
            removed += 1
        }
        if removed > 0 { save() }
    }

    // MARK: - Folders

    public func folders() -> [ListFolder] {
        let descriptor = FetchDescriptor<ListFolder>(
            sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.name)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    @discardableResult
    public func createFolder(named name: String) -> ListFolder {
        let folder = ListFolder(name: name, sortIndex: folders().count)
        context.insert(folder)
        save()
        return folder
    }

    public func deleteFolder(_ folder: ListFolder) {
        context.delete(folder)
        save()
    }

    /// Moves a list into a folder, or out of all of them when `folder` is nil.
    /// A list belongs to at most one folder, matching how Reminders behaves.
    public func assign(listID: String, to folder: ListFolder?) {
        for existing in folders() where existing.listIDs.contains(listID) {
            existing.listIDs.removeAll { $0 == listID }
        }
        if let folder, !folder.listIDs.contains(listID) {
            folder.listIDs.append(listID)
        }
        save()
    }

    public func save() {
        guard context.hasChanges else { return }
        do { try context.save() } catch {
            // The sidecar is recoverable metadata, not source of truth. Losing a write
            // costs a manual reordering, so log and carry on rather than tearing down.
            print("[MetaStore] save failed: \(error)")
        }
    }
}
