# Changelog

All notable changes to Reminders Companion are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased] — iPhone companion

### Added

- **`RemindersCompanionMobile`**, an iPhone companion app sharing `RemindersCore` with the
  Mac. Three tabs: Today, Week, and Triage.
  - **Week** is a single vertical column of days with tasks flat beneath each — not
    subdivided by list, which costs more in scrolling than it returns on a phone.
  - An always-visible **7-day strip** pins to the top of the Week view. It doubles as a
    jump control and as drop targets, so a long-press drag can reach any day without
    scrolling mid-gesture.
  - **Triage** holds the two piles that would clog the day and week views — past due and
    no-date — behind a segmented control, with a tab badge when the backlog is not empty.
  - Swipe to complete; swipe for Today/Tomorrow in Triage, where a drag cannot cross tabs.
  - Task sheet with notes, dates, priority and list. Alarms and recurrence read-only, as
    on the Mac.
  - Two-step setup: access, then list picking.
- `project.yml` for XcodeGen, so the iOS project is generated from a reviewable spec
  rather than a checked-in `.pbxproj`.

### Verified

- **Completing a repeating reminder is safe.** This was the last open question that could
  have damaged real data: if EventKit did not roll a series forward the way Reminders' own
  UI does, ticking a repeating task would have silently ended it. Run as a diagnostic
  against a Simulator's disposable database — completing today's occurrence left an
  incomplete one due tomorrow with its recurrence rule intact. The warnings in both apps
  have been corrected accordingly. See `RecurrenceDiagnostic.swift`.

### Fixed

- **Drag-to-reschedule did not work on iPhone.** Two real defects, not just remote-session
  latency:
  - `.dropDestination` was attached to a `List` `Section`, which cannot host one — most of
    the week had no valid drop area at all. The week is now a `ScrollView` of day blocks,
    each a genuine drop target covering its header, rows and empty space.
  - `.swipeActions` and `.draggable` were on the same row. Both want a press-and-move and
    inside a `List` the swipe always wins. A row now does one or the other: the week
    drags, Today and Triage swipe.
- Dragging shows a compact capsule preview rather than the full row, which is far too tall
  to aim with.
- Added tap-only rescheduling (Today / Tomorrow / +1 Week) to the task sheet, since drag is
  unusable over a remote session or one-handed.

- **`EKErrorNoStartDate` on iOS.** The SDK requires a start date whenever a due date is
  set — explicitly not a macOS requirement — and three paths wrote due dates without one
  (`setDueDay`, `create`, and the sample bill). They would all have failed to save on
  iPhone. The generated start is the **due day itself**, so `boardDay` and
  `spansMultipleDays` are unchanged and a task renders identically on both platforms.
- `openPrivacySettings` now has a UIKit branch.

### Notes

- The iPhone app deliberately has no folders, manual ordering or estimates. Those live in
  a local sidecar that does not sync, and the phone is a companion rather than the place
  you organise from.

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
