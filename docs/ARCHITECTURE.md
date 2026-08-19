# Architecture

How Reminders Companion is put together across macOS, iPhone and Apple Watch.

Written for review: the last section names the seams I would look at hardest.

---

## The shape

One core, four surfaces. Nothing has its own copy of the domain logic.

```
                        ┌──────────────────┐
                        │  Apple Reminders │   ← the only source of truth
                        │    (EventKit)    │
                        └────────▲─────────┘
                                 │
                     ┌───────────┴───────────┐
                     │     RemindersCore     │  no UI, 143 unit tests
                     │  macOS · iOS · watchOS│  the only thing touching EventKit
                     └───┬─────┬─────┬───────┘
             ┌───────────┘     │     └──────────────┐
             │                 │                    │
    ┌────────▼────────┐ ┌──────▼───────┐  ┌─────────▼─────────┐
    │ RemindersCompan.│ │ …Mobile      │  │ …Watch            │
    │   (macOS app)   │ │ (iPhone app) │  │ (watchOS app)     │
    └─────────────────┘ └──┬────────┬──┘  └────┬──────────┬───┘
                           │        │          │          │
                  ┌────────▼──┐  ┌──▼──────────▼──┐  ┌────▼──────────┐
                  │ …Widgets  │  │RemindersShared │  │…WatchWidgets  │
                  │(iOS ext.) │  │ WatchBridge    │  │(watchOS ext.) │
                  └───────────┘  │ iOS + watchOS  │  └───────────────┘
                                 └────────────────┘
```

`RemindersShared` exists solely so the Mac never links WatchConnectivity, which it has no
use for.

---

## The central design decision

Reminders has two date fields per task. This app assigns them distinct meanings:

| Field | EventKit | Meaning here |
|---|---|---|
| **Planned day** | `startDateComponents` | "I'll do this Thursday" |
| **Deadline** | `dueDateComponents` | "This is actually due Friday" |

Everything follows from that. Dragging a card writes **only** the start date, so a
deadline and its notification are never disturbed by planning. A task whose two dates
differ renders as a multi-day span. Because both are native fields, a plan made on the Mac
is already on the iPhone and Watch before this app exists on them — **there is no sync
layer, because there is nothing to sync.**

### The sidecar

Reminders has nowhere to put manual ordering, time estimates, or folders. Those live in a
local SwiftData store (`MetaStore`), keyed on `calendarItemExternalIdentifier` — the
identifier EventKit documents as sync-stable, unlike `calendarItemIdentifier`.

The sidecar is deliberately **subordinate**: losing it costs organisation, never tasks.
That asymmetry is why it never holds anything Reminders could have held. It is also
local-only, which is why the iPhone and Watch do without folders and manual order rather
than inventing a second ordering that disagrees with the Mac's.

---

## Modules

### `RemindersCore` — 19 files, ~2,450 lines, no UI

The only code that touches EventKit. Everything it publishes is a value type, so no view
ever holds a live `EKReminder` — those are mutable references tied to one `EKEventStore`
and go stale across the fetch → mutate → refetch cycle.

| | |
|---|---|
| `ReminderStore` | `@MainActor @Observable`; access, fetch, every write, change observation |
| `Scheduling` | every date conversion, including the all-day coercion rule |
| `Day` | a calendar day with no time and no timezone — the unit the boards deal in |
| `TaskItem`, `TaskList`, `Priority` | the domain model |
| `QuickAddParser` | `!` priority, `#list`, natural-language dates |
| `Ranking` | fractional indexing for manual order |
| `MetaStore`, `TaskMeta`, `ListFolder` | the sidecar |
| `WidgetDataProvider` | sidecar-free read path for extensions and the Watch |
| `UndoableAction`, `OptimisticCompletions` | undo, and the Watch's pending-write state |
| `Recurrence`, `CalendarEvent`, `BacklogSort`, `WidgetKind` | supporting types |

### `RemindersCompanion` — macOS, ~3,400 lines

The tool you plan in. Week board with drag-to-schedule, kanban Today view, Reminders-style
sidebar with user-defined folders, calendar overlay, full task detail panel, ⌘Z undo.

### `RemindersCompanionMobile` — iPhone, ~1,900 lines

The companion you update on the road. Three tabs (Today, Week, Triage), a vertical week
rather than a board, quick-add sheet, floating + button, undo banner. Deliberately thinner:
no folders, no manual ordering, no estimates.

### `RemindersCompanionWidgets` — iOS extension, ~430 lines

Today and Next Up, spanning Home Screen and Lock Screen families. Tap-to-complete via
`AppIntent`. Reads through `WidgetDataProvider` rather than `ReminderStore`, because a
widget is a separate short-lived process with no reason to spin up SwiftData for
information it never displays.

### `RemindersCompanionWatch` + `…WatchWidgets` — watchOS, ~260 lines

A Today list and watch-face complications. Reads directly through `WidgetDataProvider`;
**cannot write at all** (see below), so completions are proxied to the iPhone.

### `RemindersShared` — iOS + watchOS only, ~150 lines

`WatchBridge`, wrapping `WCSession`. Sends immediately when the phone is reachable and
falls back to `transferUserInfo`, which queues and is delivered guaranteed — that fallback
is what makes completing a task on a run with the phone at home actually land.

---

## What each platform permits

This drove more of the design than any product decision.

| | macOS | iOS | watchOS |
|---|---|---|---|
| Read reminders | ✅ | ✅ | ✅ |
| Write reminders | ✅ | ✅ | ❌ `__WATCHOS_PROHIBITED` |
| Due date without a start date | ✅ | ❌ `EKErrorNoStartDate` | — |
| Open a Settings pane | ✅ | ✅ | ❌ none exists |
| Own TCC grant | ✅ | ✅ | ✅ *not inherited from the phone* |

Consequences: the write surface in `ReminderStore` is guarded as **one block** for watchOS
rather than sprinkling `#if` around individual `store.save` calls — scattered guards would
leave the enclosing functions compiling while silently doing nothing. Writing a due date on
iOS always sets a start date to match, chosen as the **due day itself** so the task renders
identically on every platform. And the Watch must *request* access, not merely check it,
because there is nowhere else to grant it.

---

## Cross-cutting invariants

These are the rules that keep four surfaces from drifting apart.

1. **One completion path.** The Mac, the iPhone, the widget intent and the Watch bridge all
   call `ReminderStore.completeReminder(externalID:in:)`. Not similar code — the same
   function.
2. **Planning never touches deadlines or alarms.** Dragging writes `startDateComponents`
   and nothing else. EventKit never creates alarms on its own, so scheduling a task cannot
   change when — or whether — it notifies you.
3. **Refuse what cannot be expressed faithfully.** A repeat rule using set positions ("the
   second Tuesday of every month") is shown with a lock rather than flattened by an editor
   that only handles frequency and interval. Same for geofenced alerts. Enforced in the
   store, not just the UI, so no future caller can route around it.
4. **Value types cross every boundary.** No `EKReminder` escapes `RemindersCore`.
5. **The sidecar is never authoritative.** If it disagrees with Reminders, Reminders wins.

---

## Build

Two systems, for a reason.

- **macOS** — SwiftPM builds an executable; `make.sh` wraps it into a `.app` with the
  Info.plist TCC requires. No project file needed.
- **iOS + watchOS** — `project.yml` + XcodeGen generates the Xcode project. Signing, device
  deployment and TestFlight all require one; keeping the spec in version control means no
  20,000-line `.pbxproj` in diffs. Regenerate with `xcodegen generate` after adding files.

> Build a watch scheme with `-destination` alone. Passing `-sdk watchsimulator` forces that
> SDK onto *every* target in the scheme, including the iOS widget extension.

---

## Testing

Two layers, because one is not enough.

**Unit tests (143)** cover everything pure: date conversion and DST boundaries, the
all-day coercion rule, backlog bucketing, fractional ranking, the quick-add parser
(weighted toward the cases where a naive parser corrupts a title), undo labelling, watch
reconciliation, recurrence editability.

**Live-EventKit diagnostics** cover what unit tests cannot. Hidden `#if DEBUG` launch
arguments drive the real app against a Simulator's disposable Reminders database and write
a report: `--test-widget` (completion, quick-add, undo, widget ordering, detail fields,
alarms and repeat rules), `--test-recurring`, and the Mac's `--selftest`.

This second layer exists because **EventKit accepts writes in memory that it silently
discards on save**. Three fields behave that way — `location`, a repeat rule with no
deadline, and an all-day start date alongside a timed deadline. A green build proves
nothing about any of them. Every serious bug found in this project was found by this layer,
including one regression that a passing build actively concealed.

---

## Deliberate limitations

- **Tags, flags, subtasks, list sections and attachments are unreachable.** Absent from
  EventKit; no third-party app can read or write them. Folders here are recreated in the
  sidecar because Reminders' own hierarchy is invisible even to AppleScript.
- **`location` cannot be stored** on reminders, though the API accepts it.
- **Complication and widget refresh is budgeted by the OS** — the face can lag reality.
- **WatchConnectivity delivery is eventual.** Queued completions can arrive minutes later.

---

## Where I would look hardest, if reviewing this

Named honestly rather than left for someone to find.

1. **`ReminderStore` is large** (~640 lines) and is both the EventKit gateway and the undo
   recorder. The undo bookkeeping is threaded through `performSchedule`, `performSetDueDay`
   and `performMove` via a `recordUndo` flag. It works and is verified, but it is the file
   most likely to grow a bug through a careless edit — two of the regressions in this
   project happened there.
2. **`#if !os(watchOS)` around the write surface** is one large block. It is the right
   shape, but it means a reviewer has to trust the boundary rather than see each guard.
3. **The optimistic-completion expiry is time-based** (ten minutes). That is a heuristic,
   not a guarantee — there is no failure signal from `transferUserInfo`, so a genuinely
   lost write is indistinguishable from a slow one until the timer runs out.
4. **Undo is one step and in-memory.** Deliberate, and argued for in the code — but worth
   confirming the reasoning holds for a reviewer who expects a stack.
5. **Diagnostics live in the app targets**, behind `#if DEBUG`. Exclusion is verified by
   making a Release build fail on purpose, but they do create and delete real reminders,
   so the guard matters.
6. **Two build systems** is a real cost. Justified today; worth revisiting if the Mac app
   ever needs signing.
