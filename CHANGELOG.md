# Changelog

All notable changes to Reminders Companion are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Not yet versioned — pending review.

Since 1.2.1 this has grown from a single Mac app into four surfaces sharing one core: the
Mac app, an iPhone companion, Home/Lock Screen widgets, and an Apple Watch app with
complications. Along the way: quick-add shorthand, undo, fuller task details, and two
rounds of audit fixes.

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

[1.2.1]: https://github.com/itsbrandonlopez/reminders-companion/releases/tag/v1.2.1
[1.2.0]: https://github.com/itsbrandonlopez/reminders-companion/releases/tag/v1.2.0
[1.1.0]: https://github.com/itsbrandonlopez/reminders-companion/releases/tag/v1.1.0
[1.0.0]: https://github.com/itsbrandonlopez/reminders-companion/releases/tag/v1.0.0
