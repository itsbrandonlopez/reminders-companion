# Reminders Companion

A macOS planning board over Apple Reminders. Reminders stays the source of truth — Siri
capture and its notifications keep working untouched — and this app presents that same
data the way you actually plan: a week board you drag tasks onto, a Today view split by
client list, and a running backlog.

## Build and run

```bash
./make.sh          # builds build/RemindersCompanion.app
open build/RemindersCompanion.app
```

```bash
swift test         # 27 unit tests over the pure scheduling and ranking logic
```

Hidden diagnostic that exercises the write path against a scratch list:

```bash
open build/RemindersCompanion.app --args --selftest && cat build/selftest.txt
```

> macOS will ask for Reminders access on **every rebuild**. There is no code-signing
> identity on this machine, so the app is ad-hoc signed and TCC identifies it by cdhash,
> which changes each build. Expected; see `spike/FINDINGS.md`.

## How it maps onto Reminders

| Concept | Stored as |
|---|---|
| Planned day ("do it Thursday") | `startDateComponents` |
| Deadline ("the bill is due Friday") | `dueDateComponents` — **never written by scheduling** |
| Multi-day task | planned day → deadline span |
| Kanban column | the Reminders list (`EKCalendar`) |
| Backlog | incomplete with no dates |
| Priority | `EKReminder.priority` (1 high / 5 medium / 9 low) |
| Manual ordering, estimates | local SwiftData sidecar, keyed on `calendarItemExternalIdentifier` |
| Calendar overlay | `EKEvent`, read-only, opt-in |

Dragging a card writes a start date and nothing else. Alarms are never touched, and
EventKit never creates one on its own, so planning a task cannot change when — or
whether — a reminder notifies you.

Tags, flags, subtasks and list sections are absent from EventKit entirely and cannot be
read or written by any app. Lists are the only grouping dimension available.

## The board

```
┌────────────┬──────────────┬─────────────────────────────────┬───────────┐
│  Sidebar   │ Unscheduled  │  Mon  Tue  Wed  Thu  Fri  Sat   │  Backlog  │
│ (Reminders │ (collapsible)│  … the week, flexed to fit …    │           │
│   style)   │              │                                 │           │
└────────────┴──────────────┴─────────────────────────────────┴───────────┘
```

- **Unscheduled** (left, collapsible) — tasks with no date at all. The pool you plan from.
  Has its own list filter, separate from the board's: an archival list can be kept out of
  the planning pool while its dated tasks still appear on their days.
- **The week** — day columns share the leftover width so a whole week is visible without
  scrolling sideways.
- **Backlog** (right) — work that slipped past the *entire* current week. Something due
  Monday when today is Tuesday is not backlog; it stays on Monday, where the week in
  progress can still absorb it. Anchored to today, not to the week being viewed, so paging
  forward to plan next week never sweeps this week's work into it. See `BucketTests`.

The sidebar copies Reminders: smart tiles above a "My Lists" section. Flagged and
Completed are absent because flags have no API at all and completed items need a separate
fetch; Backlog takes their place. Clicking a list drills into it. The **checkmark menu**
(the filter icon beside "My Lists", also in the toolbar) chooses which lists take part in
the Week and Today boards — excluded lists stay visible but dimmed, so it is obvious why
their tasks are missing.

## Folders

Reminders folders **cannot be read by any API**, so these are recreated in the app rather
than mirrored. Verified two ways:

- EventKit has no group, folder, parent or hierarchy concept at all — grepping the whole
  framework returns nothing.
- Reminders' own AppleScript interface exposes a `container` property that can be an
  account *or* another list, which looks promising — but a list inside a folder is
  invisible to it. `every list` returned only the two un-foldered lists, and
  `list "Projects"` errors with -1728 while `list "Grocery"` resolves fine.

So folders live in the sidecar: create them with the folder button beside "My Lists", then
drag a list onto a folder or use its **Move to Folder** context menu. Deleting a folder
only ungroups its lists; nothing in Reminders is touched. "Personal" and "Work" are created
once on first launch as a starting point.

## Today

One column per Reminders list, plus a single **Backlog** vertical at the right holding
everything whose day has already passed — missed deadlines and work planned for a day
that has gone by. Deliberately not split by client: overdue work is one pile you triage
top to bottom, oldest first, and scattering it across five columns is what let it slip.
*Move All to Today* sweeps the pile in one click.

Overdue items are pulled *out* of the client columns, so a column shows only what is
genuinely due today.

## Calendar overlay

Read-only. Events from calendars you tick in the sidebar are drawn at the top of each day
column, with the hours already booked badged on the day header — so "can I take this on
Thursday?" is answerable without leaving the board.

Calendar access is a **separate permission** from Reminders and is requested only when you
switch the overlay on from the sidebar, so declining it costs nothing and the rest of the
app is unaffected. The chosen calendars persist across launches; the first time you enable
it, a calendar named "Work" is picked automatically if one exists.

Events are never created, modified or deleted.

## Layout

- `Sources/RemindersCore/` — no UI, unit-testable
  - `ReminderStore` — the only type that touches EventKit
  - `Scheduling` — the all-day coercion rule that keeps timed deadlines intact
  - `Ranking` — fractional indexing for drag-to-reorder
  - `MetaStore` / `TaskMeta` — the sidecar
- `Sources/RemindersCompanion/` — SwiftUI app
  - `Theme.swift` — the Things-style palette, resolved per appearance at draw time
- `spike/` — the Phase 0 probe and its findings
