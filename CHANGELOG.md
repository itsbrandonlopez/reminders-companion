# Changelog

All notable changes to Reminders Companion are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
