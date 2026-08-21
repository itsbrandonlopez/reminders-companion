# Changelog

All notable changes to Reminders Companion are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.4.1] — 2026-08-20

### Fixed

- **Fixed a crash on launch for builds without the CloudKit entitlement.** The sidecar
  decided whether to sync through iCloud by checking whether the device had any iCloud
  account signed in, not whether the build itself carried the CloudKit container
  entitlement — so a build without it still tried to open a CloudKit-backed store, which
  CloudKit doesn't fail gracefully on but crashes outright. Now checked directly before
  ever attempting the cloud open.

## [1.4.0] — 2026-08-20

Mac app navigation reshaped around what each view is actually for — and the sidecar,
which had quietly become the place your arrangement lives, learned to sync.

### Changed

- **A list in the sidebar now opens that list.** Every task in it, dated or not, in manual
  order, as a flat Reminders-style view with inline reordering and the same detail popover
  and right-click menu the board cards have. Clicking a list used to open the *week board*
  narrowed to it — a smaller question than the one a list row asks, and one that hid every
  undated task in the list, which for most lists is most of them.
- **Week and Today are views in their own right**, selected from the sidebar rather than
  derived from whichever tile was last clicked.
- **Two smart tiles instead of four.** Scheduled, All and Backlog all opened the same week
  board with a flag flipped, so they were three names for one view. Backlog was already a
  column on that board; its count survives as a badge on the Week tile, which was the part
  worth glancing at.
- **The toolbar's Week/Today picker is gone.** The sidebar is the only view selector now,
  as it is in Reminders — two controls over one piece of state is one too many.
- **The per-column add fields are replaced by one floating + button**, bottom-right, over
  every view. Clicking it opens a compose field in the column the view implies; **dragging
  it onto a column opens the field there** — a day on the Week board, a client column on
  Today, the list you are in. That is how "new task, on Thursday, for this client" gets
  said without typing a date or a `#list` token. ⌘N opens the same field.
- The compose field stays open after each submit, as Reminders' own new row does, and
  closes on Escape or on losing focus while empty.
- **The Today board's calendar events are a vertical timeline down the side** instead of a
  horizontal row of chips across the top. The row gave a ten-minute call and a six-hour gig
  the same size and pushed the actual work down the screen; a timeline draws them to scale,
  with hour gridlines, a now-line, side-by-side lanes for overlapping events, and an
  opening scroll position an hour before now. All-day events become one-line mentions above
  the grid. The rail is pinned outside the horizontal scroll view, so scrolling to the
  fifth client column never scrolls the day's shape away, and it folds to a strip
  (persisted). It appears only once calendars have actually been picked.

### Added

- **List sections, as Kanban columns.** A list with sections renders as a board of columns
  — the same shape Reminders gives a sectioned list — with drag between columns, drag to
  reorder within one, an "Add Section" ghost column at the end, and rename/reorder/delete
  per column. A list with no sections stays flat, so the presence of sections *is* the
  toggle and there is no second control to disagree with the content.
- Sections cannot be read from Reminders by anyone, and this was verified rather than
  assumed: no "section" anywhere in the macOS 26.5 EventKit headers, three classes in
  Reminders' AppleScript dictionary with no section among them, and a TCC-protected private
  store whose schema is Apple's to change. So they are typed once here and matched by name,
  exactly the bargain `ListFolder` already makes. New `ListSection` model, `TaskMeta`
  gains `sectionID`, five new sidecar tests.
- Deleting a section re-files its tasks as unsectioned and closes the gap in the sort
  order; it never touches a task.
- "Move to Section" in the task right-click menu, shown only for a list that has sections.

- **The sidecar syncs through iCloud**, so manual order, estimates, folders and sections
  reach every device instead of living on one Mac. `MetaStore` is now a CloudKit-backed
  SwiftData store, gated: it checks iCloud availability, attempts the CloudKit
  configuration, and falls back to a local store on any failure, reporting which through
  `MetaStore.Storage`. The sidebar says which one is in force, because an app that quietly
  is not syncing is worse than one that admits it.
- **The iPhone opens the same sidecar** and gained a fourth tab, **Lists** — your lists,
  and inside them the sections arranged on the Mac, rendered as headers rather than
  columns. The phone also honours the manual order you dragged out on the Mac; without a
  sidecar it still falls back to priority-then-day, exactly as before.
- Signing is what decides whether any of it syncs. iCloud entitlements are only honoured
  under a real identity, so `make.sh` passes them only when `CODESIGN_IDENTITY` is set and
  ad-hoc signs otherwise, and `project.yml` leaves the iOS entitlements empty until
  `MOBILE_ENTITLEMENTS` is exported — otherwise switching iCloud on breaks simulator
  builds, which need no signing at all today. Both are documented in the README.

### Fixed

- **Sidebar rows could only be clicked on their text.** A row's background is a shape
  filled with `.clear` when it is neither selected nor hovered, and SwiftUI does not
  hit-test a clear fill — so the row looked like a target the whole way across but only
  responded on the icon and the name. Affected list rows, folder headers and the calendar
  toggles; all three now set an explicit `contentShape`.

### Internal

- `SidebarFocus` narrowed from five cases to three, one per kind of view.
- `ComposeTarget` makes "where a new task lands" a value rather than a property of whatever
  text field happened to hold focus — which is what lets the + be dragged.
- `DragPayload.decode` became `DragPayload.kind`, returning a three-case enum: a card body,
  a span handle, or the + button.
- The task right-click menu is extracted as `TaskMenu`, shared by board cards and list rows.
- **CloudKit reshaped the sidecar schema.** It supports no unique constraints, so
  `TaskMeta.externalID` lost `@Attribute(.unique)` — the thing that made a second row for
  one task impossible. `MetaStore.deduplicate()` replaces it, merging rival rows field by
  field so a value one device holds is never dropped because the other saw the task more
  recently; it runs from `indexedByExternalID()`, which every refresh already calls. Every
  stored property gained a default, as CloudKit also requires. Five new tests cover it.
- The store is copied to `default.store.pre-cloudkit-backup` once before the first open
  under the new schema, since that open drops a constraint and the file now holds
  hand-typed sections that exist nowhere else.
- `ReminderStore.create` returns the new reminder's external identifier, so a caller can
  attach sidecar state to it instead of guessing which refreshed task is the new one by
  title. `TaskCardView` gains `showsList`, off inside a single list where every card would
  otherwise repeat the same name and colour.

## [1.3.0] — 2026-08-19

Since 1.2.1 this has grown from a single Mac app into four surfaces sharing one core: the
Mac app, an iPhone companion, Home/Lock Screen widgets, and an Apple Watch app with
complications. Along the way: quick-add shorthand, undo, fuller task details, and three
rounds of audit fixes.

Bundle versions are aligned with the tag from this release on. Before it the Mac app
reported `0.1` and the iOS and watchOS targets `1.0`, none of which matched the repository's
own tags — so anyone reading About on the Mac app saw a number three releases behind.

### Added

**iPhone companion** — `RemindersCompanionMobile`, sharing `RemindersCore` with the Mac.
Three tabs: Today, Week, Triage.

- **Week** is a single vertical column of days with tasks flat beneath each, not
  subdivided by list — that nesting costs more in scrolling than it returns on a phone.
- An always-visible **7-day strip** pinned to the top doubles as a jump control and as
  drop targets, so a long-press drag reaches any day without scrolling mid-gesture.
- **Triage** holds the two piles that would clog the day and week views — past due and
  no-date — behind a segmented control, badged when the backlog is not empty.
- Swipe to complete; swipe for Today/Tomorrow in Triage, where a drag cannot cross tabs.
- Two-step setup (access, then list picking), and a **floating + button** overlaid once
  above the `TabView` — one instance, one position, outside every `NavigationStack` so
  scrolling can never clip it.

**Widgets** — two kinds spanning Home Screen and Lock Screen (and StandBy, which reuses the
Lock Screen families).

- **Today** — small/medium/large plus circular/rectangular/inline. Small shows a count with
  an overdue badge; medium and large list the tasks with a real tap-to-complete checkbox.
- **Next Up** — the single next thing due, for the Lock Screen glance. Read-only at every
  size: a bare checkbox with no context is not worth the tap it saves.
- **Tap-to-complete via `AppIntent`**, with no app launch. Calls
  `ReminderStore.completeReminder(externalID:in:)` — the same function the Watch bridge
  uses, so every surface completes a task through one code path rather than several that
  drift.
- A `reminderscompanion://` URL scheme so Lock Screen widgets deep-link into the app.

**Apple Watch** — a Today list on the wrist plus watch-face complications (circular,
rectangular, inline, corner).

- **`WatchBridge`** in a new `RemindersShared` target (iOS + watchOS only) carries
  completions to the iPhone: `sendMessage` when reachable, falling back to
  `transferUserInfo`, which queues and is delivered guaranteed. Completing a task on a run
  with the phone left at home lands on reconnect.
- `OptimisticCompletions` hides a tapped row immediately and reconciles when the write
  returns through sync, releasing entries that expire or come back un-completed.

**Quick add** — shorthand shared by both apps via `QuickAddParser`.

- `!` / `!!` / `!!!` for priority; `#list` to file it, matched case-, space- and
  diacritic-insensitively so `#cafelopez` finds "Café Lopez" (exact beats prefix, so
  `#work` cannot be stolen by "Work Archive").
- Natural-language dates: `today`, `tonight`, `tomorrow`/`tmw`, `next week`, `in 3 days`,
  weekday names, `next friday`.
- **Task creation on iPhone**, which previously did not exist at all — the phone could
  complete, reschedule and edit, but not add. The sheet shows a live "Will create" summary
  before saving, so a mis-parse is visible rather than discovered later.

**Undo** — covers every reversible edit: rescheduling (including drag-to-a-day), deadline
changes, list moves, bulk reschedules and completion. **⌘Z** on Mac, an auto-dismissing
banner on iPhone. Deliberately one step, not a stack.

**Task details** — the Mac panel now carries everything Reminders exposes and permits.

- Editable **time of day** on a deadline, **URL**, **notification** and **repeat rule**.
- A **confirmation before overriding Reminders**, shown only when something is actually
  being replaced — adding an alert to a task that had none is not destructive.

### Changed

- **The detail panel follows Reminders' own info popover**: plain free-text fields at the
  top, then date rows, then menus — labels left, controls right, hairline separators
  instead of boxes. Nobody should have to learn a second layout for the same information.
  "Plan for" keeps a distinct name because a do-date is this app's idea; Reminders has no
  equivalent.
- **`RemindersCore` now compiles for macOS, iOS and watchOS.** The write surface is guarded
  as one block for watchOS rather than sprinkling `#if` around individual `store.save`
  calls, which would leave the enclosing functions compiling while silently doing nothing.
- **Every development hook is compiled out of Release builds** — `--seed-demo`,
  `--test-widget`, `--test-recurring`, `--tab`, `--selftest`, `--appearance`, and the
  diagnostic types themselves. They create and delete real reminders. Verified by making a
  Release build fail on purpose against an unguarded reference.
- Shared logic moved into `RemindersCore` so extensions and diagnostics exercise the same
  code, not copies: `WidgetDataProvider`, `WidgetKind`, `SendableCompletion`,
  `ReminderStore.makeTaskItem`, `OptimisticCompletions`.
- `project.yml` + XcodeGen generates the Xcode project from a reviewable spec rather than a
  checked-in `.pbxproj`.

### Fixed

**Two audit rounds, fifteen findings.**

- **Undo silently stopped working during rapid editing.** The iPhone banner's auto-dismiss
  used `try? await Task.sleep` then dismissed unconditionally — `try?` swallows
  cancellation, so a banner replaced by a newer action ran on and cleared *that* action's
  undo slot.
- **"Move All to Today" had no undo** — the most far-reaching action was the only
  irreversible one. It now records each task's own prior day and restores individually.
- **"Next Up" showed the highest-priority task, not the nearest**, reading the first item
  off a priority-sorted list.
- **The Today widget and Today tab disagreed on screen**, the widget sweeping in overdue
  tasks the app routes to Triage.
- **The Watch app never requested Reminders access**, only checked it — and watchOS has no
  Settings pane to grant it afterwards, so every new user would have been stranded.
- **A failed Watch completion hid its row for the whole session**, because "still in the
  fetch" is exactly what a write that never landed produces.
- **The iPhone set up the Watch bridge from a view's `.task`**, so the receiver did not
  exist during the background launch that delivers queued completions — the headline case.
- **Drag-to-reschedule did not work on iPhone**: `.dropDestination` was on a `List`
  `Section`, which cannot host one, and `.swipeActions` and `.draggable` competed for the
  same gesture.
- Clearing a deadline had no undo; deleting left a stale undo offer; a failed bulk commit
  hid its real error; nothing reloaded the watch complication; the watch list never
  refreshed after first appearance; retried Watch sends could double-deliver; duplicated
  types across targets.
- **`EKErrorNoStartDate` on iOS** — the SDK requires a start date whenever a due date is
  set, which macOS does not. Three paths wrote due dates without one and would all have
  failed to save on iPhone.
- A patch dropped `satisfyStartDateRequirement` from `setDueDay`, silently regressing that
  same fix. Caught by extending the live-EventKit diagnostic rather than trusting a build.

### Fixed — third audit pass

**A geofence alarm could be destroyed by an ordinary edit.** `setAlarm` and `setRecurrence`
guarded against clobbering things this app cannot rebuild, but they read the caller's
`TaskItem` — a snapshot taken whenever the view last refetched, which every detail panel
holds open for as long as it is on screen. Add a location alert on another device, edit the
notification here, and the guard passed on stale empty alarms while the write cleared the
live reminder's. Guards now run inside `mutate`, against the same `EKReminder` the save
touches, via a `throws` closure and a `Refusal` error. The same staleness made
`setRecurrence` both refuse valid edits and let a rule through to a reminder with no
deadline — where EventKit accepts it and silently discards it on save.

This is the finding that mattered most, because it made cross-cutting invariant #3
("enforced in the store, not just the UI, so no future caller can route around it") untrue
as written: any caller routed around it simply by holding a value type for a few seconds.

**Undo recorded the wrong "previous" value, for the same reason.** Every undo entry took the
field's prior value from the caller's `TaskItem`, so two edits to one field from a single
open detail panel both recorded the *original* value — undoing the second jumped past the
first rather than reversing it. All five recording sites now read the live reminder before
writing. They also honour whether the save landed: a refused or failed edit previously still
posted an undo banner offering to overwrite the current value with a stale one.

**External changes could be missed indefinitely.** The echo suppression around
`EKEventStoreChanged` *dropped* any notification arriving within a second of a local write.
That notification is never redelivered, so an iCloud push landing just after you ticked
something off was lost outright, not merely late. It now backs off to a longer debounce
instead of skipping.

**Concurrent refreshes could publish stale data.** `refresh()` is `@MainActor` but not
serialized — `await fetch` is a suspension point — so an older snapshot could overwrite a
newer one depending on which EventKit callback returned last, and the first one to finish
cleared the spinner for all of them. A generation counter now discards overtaken runs.

**The iOS Today widget's overdue count was wrong.** It filtered *today's* tasks for overdue
items, which finds only tasks explicitly re-planned for today that still carry a past
deadline — so it showed "0 overdue" beside a backlog of thirty, while the watch face, using
`overdueCount()`, showed the real figure.

**Backlog and Overdue were two different sets sharing one name and one control.** The Week
board's backlog is work that slipped past the *whole* current week; the Today board's was
everything whose day has gone. Both rules are right for their board — but they were both
labelled BACKLOG and governed by one sort preference documented as answering "the same
question". They are now named apart, with `AppEnvironment.overdue` alongside `backlog` and a
sort control each. The phone's `pastDueCount` became `backlogCount`, since it counts the
backlog pile and not past deadlines.

**`#423` was eaten out of task titles.** Any `#token` was treated as a list name, so "Fix
login bug #423" became "Fix login bug" filed in the default list. A token now has to contain
a letter — the same "a wrong guess is worse than no guess" rule the date parser already
applied, and which this violated.

**Times ignored the 24-hour clock.** Ten `DateFormatter()`s with hardcoded patterns
(`"h:mm a"`, `"MMM d"`) across five files rendered 13:30 as "1:30 PM" regardless of region,
and each was constructed inside a computed property called from a SwiftUI body. They are now
locale templates built once in `RemindersCore.DateLabels`. Times consequently render with
the narrow no-break space before AM/PM that CLDR specifies and the system's own apps use.

### Changed — scalability

Behaviour is identical; the cost is not. Everything here was invisible at 50 reminders and
dominant at 10,000.

- **`MetaStore` lookups were one predicate fetch per task.** `refresh()` did *n* round trips
  into SwiftData, and `applyLocalRanks()` did *n* more on the drag path whose entire purpose
  is to feel instant. Both take an index once now, and a column respread is a single
  transaction rather than a fetch plus a save per card.
- **The phone kept a sidecar it never read.** The comment claimed an in-memory store; the
  code opened a persistent one and reconciled a row per reminder on every refresh, for
  manual order and estimates the phone does not show. `ReminderStore`'s sidecar is now
  optional and the phone passes none.
- **Derived slices are computed once per change, not per access.** `filteredTasks`,
  `backlog`, `tasks(on:)` and the sidebar counts each recomputed from `store.tasks` on every
  read, and SwiftUI reads them repeatedly — a week board render came to roughly 95 full
  traversals and 40 sorts of the whole array. They are cached behind a key naming everything
  they depend on. Measured on device: 19 slice reads, 1 rebuild.
- **Widgets and complications fetch once per entry.** The watch complication built three
  `EKEventStore`s and read the whole database three times to produce two integers and a
  task — in the tightest memory and time budget in the system. `WidgetDataProvider.snapshot()`
  does it in one.
- Committing a task's text is one write. The detail panel spawned three detached `Task`s for
  title, notes and URL, giving three commits and three full refetches per "Done", in no
  guaranteed order.

### Fixed — tests that could not fail

- **`WatchRequestTests` tested a copy of the code.** It re-declared the wire keys and
  re-implemented `parse`, on the grounds that `WatchRequest` lived in an iOS/watchOS-only
  module — so renaming `completeAction` or swapping two keys left all six tests green while
  the Watch silently stopped being able to complete anything. `WatchRequest` is pure
  Foundation and now lives in `RemindersCore`; the tests call it, and pin the wire format
  explicitly.
- **The respread test asserted arithmetic, not behaviour.** It computed
  `(staleAbove + staleBelow) / 2` by hand and checked where that landed — a fact about two
  literals, true no matter what the respread path did. The path itself, including the
  fresh-neighbour re-read its comment called the whole point, had no coverage. It is now
  `Ranking.respread`, a pure function, tested directly.
- The `--selftest` "create" check passed a literal `true`. The diagnostic's "repeat with no
  deadline" line had no failure branch and conflated *the store refused* with *EventKit
  discarded it silently* — the one distinction that whole layer exists to draw.

### Verified against live EventKit

Each of these was run against real data rather than inferred from a passing build.

- **Completing a repeating reminder is safe** — it rolls the series forward with its rule
  intact, exactly as Reminders' own UI does. This was the last open question that could
  have damaged real data.
- Alarms and simple repeat rules round-trip; a repeat survives an unrelated edit.
- **A positional repeat rule is detected, refused, and left intact.** Written directly with
  EventKit, since the app cannot construct one.
- Quick-add parses to a correctly dated, prioritised and filed reminder, and a
  mid-sentence date word survives into the title.
- All four undo paths restore correctly, and bulk undo returns each task to its *own* day.
- Widget completion persists through a fresh `EKEventStore`, mirroring how an extension
  process actually runs.
- **A stale snapshot cannot destroy a geofence.** The probe writes a location alert behind a
  held `TaskItem`'s back through a second store, then edits from that snapshot, and checks
  from a third store that the geofence survived. Confirmed to *fail* against the pre-fix
  code, so it discriminates rather than merely passing.
- **Unscheduling a task that has a deadline saves, and it renders on its deadline** — the
  one scheduling gesture the Mac's `--selftest` structurally cannot cover.

### EventKit documentation that does not match observed behaviour

- **`EKErrorNoStartDate` did not reproduce.** `EKReminder`'s header states that iOS rejects
  a due date with no start date and that macOS does not. Driven against a live store on
  iOS 26, that save is **accepted** and the reminder reads back with `startDateComponents
  == nil`. Trusting the header would mean inventing a start date on every unschedule, and so
  storing different data on iPhone than the Mac stores for the identical gesture. Trusting
  the observation would mean breaking on any OS that does enforce it. The app writes what
  the user asked for and `saveRepairingStartDate` supplies a start date only for a save that
  actually comes back refused; the diagnostic prints which branch the platform took.

### EventKit behaviour worth knowing

Three fields are accepted in memory and silently discarded on save. **"It saved without
error" is not evidence it saved.**

- **`location`** — exists on `EKCalendarItem` and works for calendar *events*, but iCloud
  does not store it for reminders. Built, verified, and removed rather than shipping a
  field that quietly eats input.
- **A repeat rule with no deadline** — accepted, then dropped. The store now refuses with
  an explanation and the row reads "Needs a deadline".
- **`allDay` belongs to the reminder, not to each date** — writing an all-day planned day
  strips the time off a timed deadline. This shaped the whole date model.

Also: **watchOS EventKit is read-only** (`saveReminder`, `removeReminder`, `commit` are all
`__WATCHOS_PROHIBITED`), and building a watch scheme with `-sdk watchsimulator` forces that
SDK onto every target in the scheme — use `-destination` alone.

### Deliberate limitations

- **Tags, flags, subtasks, list sections and attachments are unreachable.** Absent from
  EventKit entirely; no third-party app can read or write them.
- **Repeat rules richer than frequency/interval/end are shown but not editable** — "the
  second Tuesday of every month" would be silently flattened by this app's editor, so it is
  locked with a pointer to Reminders. Enforced in the store, not just the UI.
- **Location-based alerts are shown but not editable** — a geofence carries coordinates and
  a radius there is no UI here to rebuild.
- The iPhone and Watch have no folders, manual ordering or estimates; those live in a local
  sidecar that does not sync.

### Not yet verified by a human

- Placing a widget on a Home or Lock Screen and tapping its checkbox.
- The Watch app against real data — a watchOS simulator's Reminders database is empty and,
  because watchOS cannot write, nothing can seed it.
- Everything above is verified in logic and against live EventKit; these three need a
  device and a person.

## [1.2.1] — 2026-08-18

### Changed

- Clicking anywhere on a task opens its details, the way a row does in Reminders. The
  hover ellipsis is gone. Dragging still works — a click opens, a drag moves — and the
  checkbox consumes its own clicks, so ticking a task never opens the panel.

## [1.2.0] — 2026-08-18

### Added

- **Task details.** A panel on every card — the ellipsis on hover, or *Show Details* from
  the context menu — showing everything Reminders holds for that task: notes, deadline,
  planned day, priority, list and estimate, all editable. Alarms, recurrence and any
  attached URL are shown read-only.
- Cards now show a **notes indicator** and, for a timed deadline, the **time of day** —
  the detail that matters on a bill and that a day column alone cannot convey.
- `create` accepts notes, a deadline and a priority, so a task no longer has to start life
  as a bare title.

### Notes

- Alarms and recurrence are deliberately read-only. Editing them well means reproducing
  Reminders' own notification rules; showing them plainly and pointing at Reminders is
  more honest than a half-built editor.
- Title and notes commit when the panel is dismissed rather than on every keystroke, since
  each write round-trips to EventKit and refetches.

## [1.1.0] — 2026-08-18

### Added

- **First-run setup.** A five-step flow that explains what the app does before asking for
  anything: the promises it makes about your data, Reminders access, choosing which lists
  to plan with, an optional calendar overlay, and a summary. Each permission is requested
  by an explicit tap *after* the reason is on screen, rather than by a bare system dialog
  on launch.
- Calendar access can be skipped outright during setup — the app is fully functional
  without it and says so.
- The setup summary offers demo tasks when an account has little in it yet.
- **Help → Run Setup Again** replays the flow without clearing preferences.

### Changed

- The app no longer requests Reminders access automatically on first launch; setup drives
  it. Once setup is complete, revoked access still shows the existing access gate rather
  than restarting onboarding.

## [1.0.0] — 2026-08-18

First release. A macOS planning board over Apple Reminders that leaves Reminders as the
source of truth.

### Added

**Week board**
- Seven day columns with drag-to-schedule. Dropping a card writes only the reminder's
  start date, so deadlines and notifications are untouched.
- **Unscheduled** column (left, collapsible) holding tasks with no date at all, with its
  own list filter separate from the board's.
- **Backlog** column (right) for work that slipped past the entire current week. Something
  due Monday when today is Tuesday stays on Monday; only once the week has rolled past
  does it fall out. Anchored to the real week, so paging ahead never sweeps current work
  into it.
- Multi-day tasks rendered as spans, with continuation chips on the days they pass through.
- Drag a card's edge handle across days to set the far end of a span.
- Drag-to-reorder within a column, backed by fractional indexing.
- Per-day totals for calendar hours booked and task estimates.
- Quick-add per column, defaulting to the list Siri writes to.

**Today board**
- One kanban column per Reminders list, so client work reads as its own lane.
- A single **Backlog** vertical for everything past due, oldest first, with a one-click
  *Move All to Today*.
- Today's calendar events across the top.

**Sidebar**
- Reminders-style layout: smart tiles (Today, Scheduled, All, Backlog) above a My Lists
  section.
- User-defined folders, since Reminders' own folders are not exposed by any API. Drag a
  list onto a folder or use its context menu. "Personal" and "Work" are created on first
  launch.
- Checkmark menus choosing which lists appear on the boards and in Unscheduled.

**Calendar overlay**
- Read-only events from calendars you pick, drawn at the top of each day column with
  booked hours badged on the day header.
- Separate, opt-in Calendar permission requested only when the overlay is switched on. A
  calendar named "Work" is selected automatically the first time.

**Getting started**
- **Help → Add Demo Tasks** creates a separate *Companion Demo* list with a dozen examples
  covering every part of the board, for trying the app against a sparse Reminders account.
  Existing lists are never touched; one action removes it again.

**Elsewhere**
- Light and dark themes resolved per appearance at draw time, following the system live.
- Undo for the last completed task.
- Priority, estimates, search, and per-list drill-in.
- Live refresh when reminders change on another device.

### Technical notes

- Planned day is stored as the reminder's start date and the deadline as its due date —
  both native fields, so the plan syncs to iPhone and Watch through iCloud and survives
  uninstalling this app.
- Alarms are never modified. EventKit does not create them on its own, so scheduling a
  task cannot change when or whether a reminder notifies you.
- Manual ordering, estimates and folders live in a local SwiftData sidecar keyed on
  `calendarItemExternalIdentifier`. Losing it costs organisation, never tasks.
- 66 unit tests over the date, ordering and event logic.

### Known limitations

- **Tags, flags, subtasks and list sections cannot be read or written.** They exist in the
  Reminders app but are absent from EventKit entirely.
- **Reminders folders cannot be read**, so folders here are recreated rather than mirrored.
  Reorganising in Reminders will not update this app.
- Completing a repeating reminder through this app has not been verified to roll the
  series forward the way Reminders' own UI does.
- macOS only. The domain logic is UI-free and platform-agnostic, so an iPhone app and
  widget can be added without rework.

[1.4.1]: https://github.com/itsbrandonlopez/reminders-companion/releases/tag/v1.4.1
[1.4.0]: https://github.com/itsbrandonlopez/reminders-companion/releases/tag/v1.4.0
[1.3.0]: https://github.com/itsbrandonlopez/reminders-companion/releases/tag/v1.3.0
[1.2.1]: https://github.com/itsbrandonlopez/reminders-companion/releases/tag/v1.2.1
[1.2.0]: https://github.com/itsbrandonlopez/reminders-companion/releases/tag/v1.2.0
[1.1.0]: https://github.com/itsbrandonlopez/reminders-companion/releases/tag/v1.1.0
[1.0.0]: https://github.com/itsbrandonlopez/reminders-companion/releases/tag/v1.0.0
