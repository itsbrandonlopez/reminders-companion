import EventKit
import Foundation

// A GUI-launched .app has no stdout, so mirror everything to a log file the
// spike can read back. TCC only prompts for a properly bundled, signed app,
// which is why this is not a plain command-line tool.
final class Out: @unchecked Sendable {
    static let shared = Out()
    private var buf = ""
    private let url: URL = {
        if let p = ProcessInfo.processInfo.environment["RC_PROBE_LOG"] {
            return URL(fileURLWithPath: p)
        }
        return URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Desktop/Gigs/RemindersCompanion/spike/probe-output.txt")
    }()
    func emit(_ s: String) {
        buf += s + "\n"
        Swift.print(s)
        try? buf.write(to: url, atomically: true, encoding: .utf8)
    }
}

func print(_ s: String = "") { Out.shared.emit(s) }

// Phase 0 round-trip spike. Answers the one question the whole design rests on:
// does `startDateComponents` written through EventKit survive Reminders + iCloud?

let scratchListName = "RC Probe"
let scratchTaskTitle = "RC Probe — start date round-trip"

// MARK: - Formatting helpers

func fmt(_ dc: DateComponents?) -> String {
    guard let dc else { return "—" }
    let hasTime = dc.hour != nil || dc.minute != nil || dc.second != nil
    let y = dc.year.map(String.init) ?? "????"
    let m = dc.month.map { String(format: "%02d", $0) } ?? "??"
    let d = dc.day.map { String(format: "%02d", $0) } ?? "??"
    var s = "\(y)-\(m)-\(d)"
    if hasTime {
        s += String(format: " %02d:%02d:%02d", dc.hour ?? 0, dc.minute ?? 0, dc.second ?? 0)
    } else {
        s += " (all-day)"
    }
    s += " tz=" + (dc.timeZone.map(\.identifier) ?? "nil/floating")
    s += " cal=" + (dc.calendar?.identifier.debugDescription ?? "nil")
    return s
}

func describe(_ r: EKReminder) -> String {
    var lines: [String] = []
    lines.append("  title      : \(r.title ?? "")")
    lines.append("  list       : \(r.calendar?.title ?? "—")  [source: \(r.calendar?.source?.title ?? "—")]")
    lines.append("  priority   : \(r.priority)")
    lines.append("  start      : \(fmt(r.startDateComponents))")
    lines.append("  due        : \(fmt(r.dueDateComponents))")
    lines.append("  completed  : \(r.isCompleted)")
    lines.append("  alarms     : \(r.alarms?.count ?? 0)")
    if let alarms = r.alarms {
        for a in alarms {
            let abs = a.absoluteDate.map { "absolute \($0)" } ?? "relative \(a.relativeOffset)s"
            let prox = a.proximity == .none ? "" : " proximity=\(a.proximity.rawValue)"
            lines.append("               • \(abs)\(prox)")
        }
    }
    lines.append("  recurrence : \(r.recurrenceRules?.count ?? 0)")
    lines.append("  itemID     : \(r.calendarItemIdentifier)")
    lines.append("  externalID : \(r.calendarItemExternalIdentifier ?? "nil")")
    lines.append("  created    : \(r.creationDate.map(String.init(describing:)) ?? "—")")
    lines.append("  modified   : \(r.lastModifiedDate.map(String.init(describing:)) ?? "—")")
    return lines.joined(separator: "\n")
}

// MARK: - Async wrappers

extension EKEventStore {
    func reminders(matching predicate: NSPredicate) async -> [EKReminder] {
        await withCheckedContinuation { cont in
            fetchReminders(matching: predicate) { cont.resume(returning: $0 ?? []) }
        }
    }
}

// MARK: - Commands

func dumpLists(_ store: EKEventStore) {
    let lists = store.calendars(for: .reminder)
    print("\n── LISTS (\(lists.count)) ───────────────────────────────")
    let defaultID = store.defaultCalendarForNewReminders()?.calendarIdentifier
    for c in lists {
        let isDefault = c.calendarIdentifier == defaultID ? "  ← Siri default" : ""
        print("  • \(c.title)")
        print("      source   : \(c.source?.title ?? "—") (\(c.source?.sourceType.rawValue ?? -1))")
        print("      editable : \(c.allowsContentModifications)   immutable: \(c.isImmutable)")
        print("      id       : \(c.calendarIdentifier)\(isDefault)")
    }
}

func dumpTasks(_ store: EKEventStore) async {
    // nil/nil range returns ALL incomplete reminders, including undated ones.
    // A bounded range silently drops undated items — which is why the app partitions in memory.
    let all = await store.reminders(matching:
        store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil))

    let undated = all.filter { $0.dueDateComponents == nil && $0.startDateComponents == nil }
    let withStart = all.filter { $0.startDateComponents != nil }
    let multiDay = all.filter { $0.startDateComponents != nil && $0.dueDateComponents != nil }

    print("\n── INCOMPLETE TASKS ─────────────────────────────")
    print("  total            : \(all.count)")
    print("  undated (backlog): \(undated.count)")
    print("  with start date  : \(withStart.count)")
    print("  start + due span : \(multiDay.count)")
    print("  with alarms      : \(all.filter { ($0.alarms?.count ?? 0) > 0 }.count)")
    print("  with priority    : \(all.filter { $0.priority != 0 }.count)")

    if !withStart.isEmpty {
        print("\n  ▸ Existing reminders that ALREADY carry a start date:")
        for r in withStart.prefix(10) { print(describe(r)); print() }
    }

    print("\n  ▸ Sample (first 8 incomplete):")
    for r in all.prefix(8) { print(describe(r)); print() }
}

func scratchList(_ store: EKEventStore, create: Bool) throws -> EKCalendar? {
    if let existing = store.calendars(for: .reminder).first(where: { $0.title == scratchListName }) {
        return existing
    }
    guard create else { return nil }
    let cal = EKCalendar(for: .reminder, eventStore: store)
    cal.title = scratchListName
    // Prefer the same source as the default list so it lands in iCloud and actually syncs.
    cal.source = store.defaultCalendarForNewReminders()?.source
        ?? store.sources.first { $0.sourceType == .calDAV }
        ?? store.sources.first { $0.sourceType == .local }
    try store.saveCalendar(cal, commit: true)
    print("  created scratch list '\(scratchListName)' in source '\(cal.source?.title ?? "—")'")
    return cal
}

func runWrite(_ store: EKEventStore) async throws {
    print("\n── WRITE TEST ───────────────────────────────────")
    guard let list = try scratchList(store, create: true) else {
        print("  ✗ could not create scratch list"); return
    }

    let existing = await store.reminders(matching: store.predicateForReminders(in: [list]))
    let reminder = existing.first { $0.title == scratchTaskTitle } ?? {
        let r = EKReminder(eventStore: store)
        r.title = scratchTaskTitle
        r.calendar = list
        return r
    }()

    var gregorian = Calendar(identifier: .gregorian)
    gregorian.timeZone = TimeZone.current
    let today = Date()
    let inThreeDays = gregorian.date(byAdding: .day, value: 3, to: today)!

    // Planned day: all-day floating date — no hour/minute/second, no timezone.
    var start = DateComponents()
    start.calendar = Calendar(identifier: .gregorian)
    start.year = gregorian.component(.year, from: today)
    start.month = gregorian.component(.month, from: today)
    start.day = gregorian.component(.day, from: today)

    // Deadline three days out, so this is also a multi-day span test.
    var due = DateComponents()
    due.calendar = Calendar(identifier: .gregorian)
    due.year = gregorian.component(.year, from: inThreeDays)
    due.month = gregorian.component(.month, from: inThreeDays)
    due.day = gregorian.component(.day, from: inThreeDays)

    reminder.startDateComponents = start
    reminder.dueDateComponents = due
    reminder.priority = 1   // high

    let alarmsBefore = reminder.alarms?.count ?? 0
    try store.save(reminder, commit: true)
    print("  saved. externalID = \(reminder.calendarItemExternalIdentifier ?? "nil")")
    print("  alarms before save: \(alarmsBefore), after save: \(reminder.alarms?.count ?? 0)")

    // Re-read from a *fresh* store to prove it hit the database, not just our object graph.
    let verifyStore = EKEventStore()
    guard try await verifyStore.requestFullAccessToReminders() else {
        print("  ✗ verify store denied access"); return
    }
    guard let verifyList = try scratchList(verifyStore, create: false) else {
        print("  ✗ scratch list not visible from fresh store"); return
    }
    let reread = await verifyStore.reminders(matching: verifyStore.predicateForReminders(in: [verifyList]))
    guard let check = reread.first(where: { $0.title == scratchTaskTitle }) else {
        print("  ✗ reminder not found on re-read"); return
    }

    print("\n  ▸ Re-read from a fresh EKEventStore:")
    print(describe(check))

    let startSurvived = check.startDateComponents != nil
    let dueSurvived = check.dueDateComponents != nil
    let idStable = check.calendarItemExternalIdentifier == reminder.calendarItemExternalIdentifier
    let noPhantomAlarm = (check.alarms?.count ?? 0) == 0

    print("\n  ▸ VERDICT")
    print("    start date persisted     : \(startSurvived ? "✓ YES" : "✗ NO")")
    print("    due date persisted       : \(dueSurvived ? "✓ YES" : "✗ NO")")
    print("    start ≠ due (multi-day)  : \(startSurvived && dueSurvived && check.startDateComponents?.day != check.dueDateComponents?.day ? "✓ YES" : "✗ NO")")
    print("    externalID stable        : \(idStable ? "✓ YES" : "✗ NO")")
    print("    no alarm auto-created    : \(noPhantomAlarm ? "✓ YES" : "✗ NO — dates alone spawned an alarm")")
    print("    priority persisted       : \(check.priority == 1 ? "✓ YES" : "✗ NO (got \(check.priority))")")
    print("\n  Now open Reminders.app → '\(scratchListName)' and confirm how this renders,")
    print("  then check your iPhone after a sync. Run `probe cleanup` when done.")
}


/// The safety-critical test: a reminder with a real alarm must come through a
/// reschedule with its alarm and due date untouched. This is what guarantees a
/// bill reminder keeps firing after you drag it around the week board.
func runAlarmTest(_ store: EKEventStore) async throws {
    print("\n── ALARM PRESERVATION TEST ──────────────────────")
    guard let list = try scratchList(store, create: true) else {
        print("  ✗ could not create scratch list"); return
    }

    let title = "RC Probe — alarm preservation"
    var gregorian = Calendar(identifier: .gregorian)
    gregorian.timeZone = TimeZone.current

    let existing = await store.reminders(matching: store.predicateForReminders(in: [list]))
    let r = existing.first { $0.title == title } ?? {
        let n = EKReminder(eventStore: store)
        n.title = title
        n.calendar = list
        return n
    }()

    // Build it the way a bill reminder looks: timed due date + absolute alarm.
    if r.alarms?.isEmpty ?? true {
        let dueDate = gregorian.date(byAdding: .day, value: 2, to: Date())!
        var due = DateComponents()
        due.calendar = Calendar(identifier: .gregorian)
        due.timeZone = TimeZone.current
        for c in [Calendar.Component.year, .month, .day] {
            due.setValue(gregorian.component(c, from: dueDate), for: c)
        }
        due.hour = 9; due.minute = 0; due.second = 0
        r.dueDateComponents = due
        r.addAlarm(EKAlarm(absoluteDate: gregorian.date(from: due)!))
        try store.save(r, commit: true)
        print("  seeded a bill-like reminder: due \(fmt(r.dueDateComponents)), alarms \(r.alarms?.count ?? 0)")
    }

    let dueBefore = r.dueDateComponents
    let alarmsBefore = (r.alarms ?? []).map { $0.absoluteDate }
    print("  before → due: \(fmt(dueBefore))  alarms: \(alarmsBefore.count) \(alarmsBefore)")

    // Now do exactly what a drag on the week board does: write start only.
    for offset in [1, 3, 5] {
        let day = gregorian.date(byAdding: .day, value: offset, to: Date())!
        var start = DateComponents()
        start.calendar = Calendar(identifier: .gregorian)
        for c in [Calendar.Component.year, .month, .day] {
            start.setValue(gregorian.component(c, from: day), for: c)
        }
        r.startDateComponents = start
        try store.save(r, commit: true)
    }

    let verify = EKEventStore()
    guard try await verify.requestFullAccessToReminders() else { return }
    guard let vList = try scratchList(verify, create: false) else { return }
    let reread = await verify.reminders(matching: verify.predicateForReminders(in: [vList]))
    guard let check = reread.first(where: { $0.title == title }) else {
        print("  ✗ not found on re-read"); return
    }

    let alarmsAfter = (check.alarms ?? []).map { $0.absoluteDate }
    print("  after  → due: \(fmt(check.dueDateComponents))  alarms: \(alarmsAfter.count) \(alarmsAfter)")
    print("  planned day now: \(fmt(check.startDateComponents))")

    let dueSame = fmt(dueBefore) == fmt(check.dueDateComponents)
    let alarmsSame = alarmsBefore == alarmsAfter && !alarmsAfter.isEmpty

    print("\n  ▸ VERDICT")
    print("    due date unchanged after 3 reschedules : \(dueSame ? "✓ YES" : "✗ NO")")
    print("    alarms unchanged after 3 reschedules   : \(alarmsSame ? "✓ YES" : "✗ NO")")
    print("    planned day moved independently        : \(check.startDateComponents != nil ? "✓ YES" : "✗ NO")")
}


/// Follow-up to the alarm test, which surfaced that an all-day `startDateComponents`
/// coerces the whole reminder to all-day and strips the time off a timed due date
/// (`allDay` is a property of the item, not of each date). This checks the fix:
/// when the due date is timed, write a *timed* start so the item stays non-all-day.
func runTimedTest(_ store: EKEventStore) async throws {
    print("\n── TIMED-START FIX TEST ─────────────────────────")
    guard let list = try scratchList(store, create: true) else { return }
    let title = "RC Probe — timed start fix"
    var gregorian = Calendar(identifier: .gregorian)
    gregorian.timeZone = TimeZone.current

    let existing = await store.reminders(matching: store.predicateForReminders(in: [list]))
    if let old = existing.first(where: { $0.title == title }) {
        try store.remove(old, commit: true)   // start clean every run
    }

    let r = EKReminder(eventStore: store)
    r.title = title
    r.calendar = list

    let dueDate = gregorian.date(byAdding: .day, value: 2, to: Date())!
    var due = DateComponents()
    due.calendar = Calendar(identifier: .gregorian)
    due.timeZone = TimeZone.current
    for c in [Calendar.Component.year, .month, .day] {
        due.setValue(gregorian.component(c, from: dueDate), for: c)
    }
    due.hour = 9; due.minute = 0; due.second = 0
    r.dueDateComponents = due
    r.addAlarm(EKAlarm(absoluteDate: gregorian.date(from: due)!))
    try store.save(r, commit: true)
    print("  seeded → due: \(fmt(r.dueDateComponents))")

    // The fix: mirror the due date's "timed-ness" onto the start date.
    let planned = gregorian.date(byAdding: .day, value: 1, to: Date())!
    var start = DateComponents()
    start.calendar = Calendar(identifier: .gregorian)
    start.timeZone = due.timeZone
    for c in [Calendar.Component.year, .month, .day] {
        start.setValue(gregorian.component(c, from: planned), for: c)
    }
    start.hour = 0; start.minute = 0; start.second = 0
    r.startDateComponents = start
    try store.save(r, commit: true)

    let verify = EKEventStore()
    guard try await verify.requestFullAccessToReminders() else { return }
    guard let vList = try scratchList(verify, create: false) else { return }
    let reread = await verify.reminders(matching: verify.predicateForReminders(in: [vList]))
    guard let check = reread.first(where: { $0.title == title }) else { return }

    print("  after  → due: \(fmt(check.dueDateComponents))")
    print("           start: \(fmt(check.startDateComponents))")
    print("           alarms: \(check.alarms?.count ?? 0)")

    let keptTime = check.dueDateComponents?.hour == 9 && check.dueDateComponents?.minute == 0
    print("\n  ▸ VERDICT")
    print("    timed due date kept its 09:00 : \(keptTime ? "✓ YES — timed start is the fix" : "✗ NO — still coerced to all-day")")
    print("    alarm intact                  : \((check.alarms?.count ?? 0) == 1 ? "✓ YES" : "✗ NO")")
}

func runCleanup(_ store: EKEventStore) throws {
    print("\n── CLEANUP ──────────────────────────────────────")
    guard let list = try scratchList(store, create: false) else {
        print("  nothing to clean up"); return
    }
    try store.removeCalendar(list, commit: true)
    print("  removed scratch list '\(scratchListName)'")
}

// MARK: - Entry

@main
struct Probe {
    static func main() async {
        let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "read"

        let status = EKEventStore.authorizationStatus(for: .reminder)
        print("Reminders authorization status (before request): \(status.rawValue) — \(label(status))")

        let store = EKEventStore()
        do {
            let granted = try await store.requestFullAccessToReminders()
            guard granted else {
                print("✗ Access denied. Grant it in System Settings → Privacy & Security → Reminders.")
                exit(1)
            }
        } catch {
            print("✗ Access request failed: \(error)")
            exit(1)
        }
        print("✓ Full access to Reminders granted.")

        do {
            switch mode {
            case "read":
                dumpLists(store)
                await dumpTasks(store)
            case "write":
                dumpLists(store)
                try await runWrite(store)
            case "alarm":
                try await runAlarmTest(store)
            case "timed":
                try await runTimedTest(store)
            case "cleanup":
                try runCleanup(store)
            default:
                print("usage: probe [read|write|alarm|timed|cleanup]")
                exit(2)
            }
        } catch {
            print("✗ \(error)")
            exit(1)
        }
        print("\n── done ─────────────────────────────────────────")
        exit(0)
    }

    static func label(_ s: EKAuthorizationStatus) -> String {
        switch s {
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .fullAccess: return "fullAccess"
        case .writeOnly: return "writeOnly"
        @unknown default: return "unknown"
        }
    }
}
