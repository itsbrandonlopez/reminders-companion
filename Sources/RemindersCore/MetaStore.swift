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

    /// Where this sidecar actually lives, which is not always where it was asked to live.
    /// Surfaced so the app can say so rather than leaving someone to wonder why their
    /// sections have not appeared on another device.
    public enum Storage: Sendable {
        /// Syncing through iCloud. Sections, order and estimates reach every device.
        case cloud
        /// This device only. Either the build carries no iCloud entitlement — an ad-hoc
        /// signed build cannot — or iCloud is unavailable to the user.
        case local
        /// Tests.
        case memory

        public var isSyncing: Bool { self == .cloud }
    }

    public private(set) var storage: Storage

    /// Must match the container created in the developer portal, and the identifier in
    /// both `.entitlements` files. Changing it strands whatever is already synced.
    public static let cloudContainerID = "iCloud.com.brandonlopez.RemindersCompanion"

    /// Whether this running process was actually signed with the CloudKit container
    /// entitlement, as opposed to whether the device merely has an iCloud account. Asking
    /// for the container's ubiquity URL is the documented, public way to find out: it
    /// resolves to nil when the process holds no entitlement for that identifier, rather
    /// than crashing the way an unentitled CloudKit database open does.
    private static var hasCloudKitEntitlement: Bool {
        FileManager.default.url(forUbiquityContainerIdentifier: cloudContainerID) != nil
    }

    public init(inMemory: Bool = false) throws {
        let schema = Schema([TaskMeta.self, ListFolder.self, ListSection.self])

        if inMemory {
            container = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            )
            storage = .memory
            return
        }

        Self.backUpStoreBeforeFirstCloudOpen()

        // Three gates, because none alone is enough. The ubiquity token only reflects
        // whether *some* iCloud account is signed into the device — it stays non-nil even
        // when this particular build carries no CloudKit entitlement at all. Asking
        // CloudKit to open a container the process isn't entitled to doesn't throw; it
        // crashes the process outright, on a background queue no `do` here can reach. So
        // the entitlement has to be checked directly before ever attempting the open.
        if FileManager.default.ubiquityIdentityToken != nil && Self.hasCloudKitEntitlement {
            do {
                container = try ModelContainer(
                    for: schema,
                    configurations: ModelConfiguration(
                        schema: schema, cloudKitDatabase: .private(Self.cloudContainerID)
                    )
                )
                storage = .cloud
                deduplicate()
                return
            } catch {
                // Never fatal. A sidecar that will not sync is worth far more than no
                // sidecar, and the local store is the same file either way.
                print("[MetaStore] iCloud unavailable, continuing on this device only: \(error)")
            }
        }

        container = try ModelContainer(
            for: schema, configurations: ModelConfiguration(schema: schema)
        )
        storage = .local
        deduplicate()
    }

    /// Copies the store aside once, before the first open under the CloudKit-shaped
    /// schema.
    ///
    /// That open drops a unique constraint and adds defaults, which SwiftData migrates
    /// automatically — but "automatically" is doing load-bearing work in that sentence,
    /// and by now this file holds hand-typed sections and folders that exist nowhere else.
    /// One copy, kept forever, is a cheap price for being able to go back.
    private static func backUpStoreBeforeFirstCloudOpen() {
        let support = URL.applicationSupportDirectory
        let store = support.appending(path: "default.store")
        let backup = support.appending(path: "default.store.pre-cloudkit-backup")
        let manager = FileManager.default
        guard manager.fileExists(atPath: store.path()),
              !manager.fileExists(atPath: backup.path()) else { return }
        // SQLite's sidecar files matter as much as the main one.
        for suffix in ["", "-wal", "-shm"] {
            try? manager.copyItem(
                at: URL(filePath: store.path() + suffix),
                to: URL(filePath: backup.path() + suffix)
            )
        }
        print("[MetaStore] backed up the sidecar to \(backup.path()) before migrating")
    }

    /// Collapses rows that describe the same task.
    ///
    /// This is what replaces the unique constraint CloudKit will not allow. Two devices
    /// working offline each create a row for the same reminder, and both arrive; the newer
    /// one wins, but only field by field, so an estimate typed on the older device is not
    /// thrown away just because the other device touched the task more recently.
    @discardableResult
    public func deduplicate() -> Int {
        var keepers: [String: TaskMeta] = [:]
        var doomed: [TaskMeta] = []

        for row in all() {
            guard let rival = keepers[row.externalID] else {
                keepers[row.externalID] = row
                continue
            }
            let (keep, drop) = Self.merge(rival, row)
            keepers[row.externalID] = keep
            doomed.append(drop)
        }

        guard !doomed.isEmpty else { return 0 }
        for row in doomed { context.delete(row) }
        save()
        return doomed.count
    }

    /// Folds two rows for one task into one. The most recently seen row is the base, and
    /// anything it has no answer for is taken from the other.
    private static func merge(_ a: TaskMeta, _ b: TaskMeta) -> (keep: TaskMeta, drop: TaskMeta) {
        let (keep, drop) = a.lastSeen >= b.lastSeen ? (a, b) : (b, a)
        if keep.estimateMinutes == nil { keep.estimateMinutes = drop.estimateMinutes }
        if keep.sectionID == nil { keep.sectionID = drop.sectionID }
        if keep.titleSnapshot.isEmpty { keep.titleSnapshot = drop.titleSnapshot }
        keep.lastSeen = max(keep.lastSeen, drop.lastSeen)
        return (keep, drop)
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
        var doomed: [TaskMeta] = []
        let rows = all()
        index.reserveCapacity(rows.count)
        for row in rows {
            // Duplicates are collapsed here rather than on a timer: this runs on every
            // refresh and already touches every row, so it is the cheapest honest place
            // to notice that iCloud has delivered a second row for a task.
            if let rival = index[row.externalID] {
                let (keep, drop) = Self.merge(rival, row)
                index[row.externalID] = keep
                doomed.append(drop)
            } else {
                index[row.externalID] = row
            }
        }
        if !doomed.isEmpty {
            for row in doomed { context.delete(row) }
            save()
        }
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

    public func setSection(_ sectionID: String?, for externalID: String) {
        meta(for: externalID)?.sectionID = sectionID
        save()
    }

    /// Files many tasks at once — what dropping a card onto a column does when the drop
    /// also reorders, and what deleting a section does to everything that was in it.
    public func setSections(_ assignments: [String: String?]) {
        guard !assignments.isEmpty else { return }
        let index = indexedByExternalID()
        for (externalID, sectionID) in assignments {
            index[externalID]?.sectionID = sectionID
        }
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

    // MARK: - Sections

    /// The sections of one list, in display order.
    public func sections(in listID: String) -> [ListSection] {
        let descriptor = FetchDescriptor<ListSection>(
            predicate: #Predicate { $0.listID == listID },
            sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.name)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    @discardableResult
    public func createSection(named name: String, in listID: String) -> ListSection {
        let section = ListSection(
            listID: listID, name: name, sortIndex: sections(in: listID).count
        )
        context.insert(section)
        save()
        return section
    }

    /// Deletes a section and returns its tasks to the unsectioned column.
    ///
    /// The tasks themselves are never touched — a section is an arrangement of a list, and
    /// deleting an arrangement must not delete what was arranged.
    public func deleteSection(_ section: ListSection) {
        let id = section.id.uuidString
        let orphans = all().filter { $0.sectionID == id }
        for row in orphans { row.sectionID = nil }
        context.delete(section)
        // Re-close the gap, so the next section created does not collide with the last
        // index and sort ambiguously against it.
        for (index, remaining) in sections(in: section.listID).enumerated() {
            remaining.sortIndex = index
        }
        save()
    }

    /// Writes a whole list's section order at once, from the order the caller displays.
    public func reorderSections(_ ordered: [ListSection]) {
        for (index, section) in ordered.enumerated() { section.sortIndex = index }
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
