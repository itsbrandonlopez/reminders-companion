# Changelog

All notable changes to Reminders Companion are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased] — Alerts and repeat rules

### Added

- **Editable notification and repeat rows** on the Mac detail panel, matching Reminders'
  own "Remind me" and "Repeat" controls.
- **A confirmation before overriding Reminders.** Changing an alert or a repeat rule the
  user already set up asks first and says plainly that the old one will be replaced. It
  appears only when something is actually being replaced — adding an alert to a task that
  had none is not destructive and does not interrupt.
- Cancelling the confirmation puts the toggles back where the reminder actually is, rather
  than leaving the UI claiming a change that never happened.

### Notes

- **This app refuses to edit rules it cannot faithfully express.** An `EKRecurrenceRule`
  can specify days of the week, days of the month, set positions and more — "the second
  Tuesday of every month". This editor covers frequency, interval and an end, so anything
  richer is shown with a lock and a pointer to Reminders instead. Overwriting it would have
  quietly turned that rule into "every 2 months" with nothing on screen to reveal the loss.
  A confirmation dialog alone would not have prevented this: the user would have clicked
  through it without knowing what was being discarded. Verified end to end by writing a
  positional rule with EventKit directly and confirming the app detects it, refuses, and
  leaves it intact.
- The same applies to **location-based alerts**: a geofence carries coordinates, a radius
  and an enter/leave direction this app has no UI to rebuild, so it is displayed and left
  alone.
- **A repeat rule needs a deadline.** Verified: adding one to a reminder with no due date
  is accepted in memory and silently discarded on save. The store now refuses with an
  explanation and the row says "Needs a deadline" rather than appearing to work.

## [Unreleased] — Task details

### Added

- **Editable time of day on a deadline.** Previously read-only with "Time of day is set in
  Reminders". A "Deadline" row now reveals an "At a time" toggle and a time picker, and
  clearing it returns the task to a genuine all-day date rather than one carrying leftovers.
- **Editable URL.**

### Changed

- **The detail panel now follows Reminders' own info popover**: plain free-text fields at
  the top, then date rows, then the menus — labels on the left, controls on the right,
  hairline separators instead of boxed fields. Nobody should have to learn a second layout
  for the same information. "Plan for" keeps a distinct name because a do-date is this
  app's idea and Reminders has no equivalent.

### Notes

- **Location was built, verified, and removed.** `EKCalendarItem.location` exists and
  EventKit accepts a value, but iCloud silently discards it for reminders — confirmed by
  writing it directly onto a live `EKReminder`, saving, and finding it gone on refetch from
  an independent store. It works for calendar *events*, which share the superclass. A field
  that quietly eats what you type is worse than no field.
- Setting a due *time* is the one field that touches the all-day coercion rule from the
  original spike, so the logic lives in `Scheduling.settingTime` as pure, tested code:
  clearing a time must drop the timezone too, or the date drifts when the machine moves.
- Alarms and repeat rules remain shown but not editable. They are the two things the user
  trusts Reminders for, and each gets its own verified pass rather than riding along here.

## [Unreleased] — Watch audit fixes

An audit of the Watch work found seven issues, two of which would have shipped broken.

### Fixed

- **The Watch app never requested Reminders access**, only checked it. watchOS carries its
  own TCC grant rather than inheriting the iPhone's, and there is no watchOS Settings pane
  to grant it afterwards — so every new user would have been stranded on "Allow Reminders
  access on your iPhone" with nothing anywhere to tap. Verified by resetting the grant and
  confirming the prompt now appears.
- **A failed completion hid its row for the whole session.** `reconcile` kept any pending
  id still present in the fetch, which is exactly what a completion that never reached the
  phone produces — so the task stayed invisible with no retry. Pending entries now expire
  after ten minutes and the row returns.
- **The iPhone set up the Watch bridge from a view's `.task`**, so the receiver only
  existed once the SwiftUI scene appeared. iOS delivers a queued `transferUserInfo` by
  launching the app in the *background*, where the scene may never appear — meaning the
  feature's headline case, completing on a run with the phone at home, could have been
  dropped entirely. Activation moved to `App.init`, and requests arriving before a handler
  is installed are now buffered and drained.
- **Nothing reloaded the watch complication.** Its kind was a bare string literal rather
  than a `WidgetKind` constant, and no code reloaded it, so the face kept a stale count
  until watchOS refreshed on its own budget.
- **The Watch list never refreshed after first appearance** — no `scenePhase` observer, so
  raising your wrist showed a snapshot from launch and tapping could re-complete something
  already done elsewhere.
- Retried sends now carry a **request id** so the phone can recognise a duplicate. Harmless
  while completion is the only action and idempotent, but the envelope is built to grow and
  the first non-idempotent action would have executed twice.
- `SendableCompletion` was duplicated in both widget targets; it now lives once in
  `RemindersCore`.

### Notes

- The theme was that **the simulator hid the two worst bugs**: its Reminders database is
  empty and unseedable, so a populated list was never seen (hiding the stale-refresh bug),
  and access had been pre-granted with `simctl privacy`, so the permission path was never
  exercised. Building was not the same as running.

## [Unreleased] — Apple Watch

### Added

- **Watch app and complications.** A Today list on the wrist, plus watch-face
  complications in circular, rectangular, inline and corner families.
- **`WatchBridge`** (new `RemindersShared` target, iOS + watchOS only) carrying completions
  from the Watch to the iPhone over WatchConnectivity. `sendMessage` when the phone is
  reachable, falling back to `transferUserInfo`, which queues and is delivered guaranteed —
  so completing a task on a run with the phone left at home still lands on reconnect.
- The phone-side receiver runs `ReminderStore.completeReminder`, the same static function
  the widget's intent uses, so the Watch, the widget and the app share one completion path
  rather than three that drift.
- `OptimisticCompletions` in `RemindersCore` hides a tapped row immediately and reconciles
  when the write comes back through sync — including releasing a task that gets
  un-completed elsewhere, which would otherwise stay invisible on the Watch forever.

### Changed

- **`RemindersCore` now compiles for watchOS.** watchOS EventKit is read-only —
  `saveReminder`, `removeReminder`, `saveCalendar`, `removeCalendar` and `commit` are all
  `__WATCHOS_PROHIBITED` — so the write surface is guarded as one block between the Writing
  and Ordering MARKs. Guarding individual `store.save` calls instead would leave the
  enclosing functions compiling on watchOS while silently doing nothing, which is worse
  than not existing.
- `SampleData` and `RecurrenceDiagnostic` are excluded on watchOS for the same reason.

### Notes

- **The Watch app cannot be verified with real data.** A watchOS simulator has its own
  empty Reminders database, and because watchOS cannot write, nothing can seed it — so it
  correctly shows "All clear" and always will. The app renders, the empty and unauthorised
  states work, and the reading path is `WidgetDataProvider`, already verified extensively
  against live EventKit on iOS. The genuinely watch-specific logic was moved into
  `OptimisticCompletions` precisely so it could be unit-tested instead.
- Building a watch scheme with `-sdk watchsimulator` forces that SDK onto every target in
  the scheme, including the iOS widget extension. Use `-destination` alone.

## [Unreleased] — Audit fixes

A full review of the ~7,200 lines added since 1.0.0 turned up eight issues, all fixed.

### Fixed

- **Undo silently stopped working during rapid editing.** The iPhone banner's
  auto-dismiss used `try? await Task.sleep` and then dismissed unconditionally — but
  `try?` swallows cancellation, so when a second edit replaced the banner the cancelled
  timer ran on and cleared the *new* action's undo slot almost immediately. Confirmed
  empirically before fixing.
- **"Move All to Today" had no undo** — the app's most far-reaching action was the only
  one that couldn't be reversed. The bulk path now records every task's own prior day and
  restores them individually, not to one shared day.
- **The "Next Up" widget showed the highest-priority task, not the nearest.** It took the
  first item from a priority-sorted list, so a high-priority task due next month beat a
  low-priority one due today. Now ordered by date, with priority breaking same-day ties.
- **The Today widget and the Today tab disagreed on screen.** The widget swept in every
  overdue task while the app routes those to Triage, so the two counts contradicted each
  other. The widget now uses the app's exact rule; overdue stays a separate badge.
- **Clearing a deadline had no undo**, while editing the same field in the detail panel
  did — so the destructive route was the unprotected one.
- **Deleting a task left a stale undo offer** that could only fail with "no longer in
  Reminders" when tapped. Deleting now retires an undo that refers to it, including one
  buried inside a bulk batch.
- A failed bulk commit had its error overwritten by the per-task failure count, hiding the
  fact that nothing was written at all.
- Fixed a doc comment left claiming the undo slot was both completion-specific and general.

### Notes

- The through-line was **inconsistent undo coverage**: four mutation paths recorded it and
  four didn't, and the gaps were the destructive ones. Every mutation now either records
  undo or is explicitly a no-op for it.
- Verified against live EventKit rather than a green build, which is what caught the last
  regression: bulk undo restores each task to its own day, and "Next Up" is asserted as a
  *property* (it equals the earliest dated task) rather than by expected title — the demo
  data's overdue high-priority item would have passed a naive check under both the old and
  new ordering.

## [Unreleased] — Undo

### Added

- **Undo now covers every reversible edit**, not just completion: rescheduling (including
  drag-to-a-day), deadline changes, and moving a task between lists. On Mac it's the
  standard **⌘Z** plus a banner; on iPhone a banner above the tab bar that auto-dismisses
  after six seconds, since a permanent undo affordance on a phone just becomes furniture.
- The banner names what happened — "Moved · Undo", "Deadline changed · Undo" — and
  distinguishes scheduling something for the first time ("Scheduled") from moving an
  already-dated task ("Moved").

### Notes

- Deliberately **one step, not a stack.** Every edit writes straight through to Reminders,
  which other devices and the Reminders app itself may be changing concurrently. A deep
  stack would accumulate entries whose original state has since been overwritten
  elsewhere, so "undo" would quietly start meaning "overwrite whatever is there now with
  something stale". One step back is what can actually be guaranteed.
- Undoing never becomes itself undoable, so the banner can't trap you in a loop.

### Fixed

- While building this, a patch dropped `satisfyStartDateRequirement` from `setDueDay` —
  silently regressing the iOS `EKErrorNoStartDate` fix, which would have made setting a
  deadline fail to save on iPhone for any task without a planned day. Caught by extending
  the diagnostic to verify undo against live EventKit rather than trusting the build.

## [Unreleased] — Release hygiene

### Changed

- **Every development hook is now compiled out of Release builds.** `--seed-demo`,
  `--test-widget`, `--test-recurring`, `--tab` and the Mac's `--selftest` and
  `--appearance`, along with `WidgetDiagnostic`, `SelfTest` and `RecurrenceDiagnostic`,
  all sit behind `#if DEBUG`. They create and delete real reminders, which has no place in
  a shipping binary.
- Collected into `DebugHooks` in each app rather than scattered inline, so the shipping
  code path reads without conditionals threaded through it.
- Verified by making a Release build fail on purpose: an unguarded reference to
  `WidgetDiagnostic` from shipping code produces "cannot find 'WidgetDiagnostic' in
  scope", proving the exclusion is real rather than assumed. Debug hooks confirmed still
  functional afterwards.

## [Unreleased] — Quick add

### Changed

- Task creation on iPhone moved from a toolbar button to a **floating circular + in the
  bottom right**, overlaid once above the `TabView` rather than repeated per tab — one
  instance, one position, and it sits outside every `NavigationStack` so scrolling can
  never clip or scroll it away. Its default day still follows the visible tab.
- Each scrollable list gained bottom clearance so content can always be scrolled out from
  under the button, rather than the last row sitting permanently beneath it.

### Added

- **Quick-add shorthand**, shared by both apps via a new `QuickAddParser` in
  `RemindersCore`:
  - `!` / `!!` / `!!!` for low / medium / high priority
  - `#list` to file it, matched case-, space- and diacritic-insensitively so `#cafelopez`
    finds "Café Lopez" (an exact match always beats a prefix match, so `#work` can't be
    stolen by "Work Archive")
  - Natural-language dates: `today`, `tonight`, `tomorrow`/`tmw`, `next week`,
    `in 3 days`, weekday names, and `next friday`
- **Task creation on iPhone**, which previously did not exist at all — the phone could
  complete, reschedule and edit, but not add. A **+** on all three tabs opens a quick-add
  sheet whose defaults follow context: Today creates for today, Week for the week you're
  looking at, Triage's no-date pile creates undated.
- The sheet shows a live **"Will create"** summary — resolved title, list, day and
  priority — before anything is saved, so a mis-parse is visible rather than discovered
  later.

### Notes

- **A date phrase is only recognised at the very start or end of the input.** This is the
  rule that keeps "Prep Tuesday's invoice" and "Move the Friday meeting" intact: a date
  word mid-sentence is part of the sentence. Silently eating a real word out of a title is
  a worse failure than not parsing, because the damage stays invisible until the user goes
  looking for the task.
- Sigils (`!`, `#`) may appear anywhere, since nothing else in a title plausibly looks like
  a standalone `!!!` or a `#word`. An exclamation attached to a word — "Ship it!" — is
  punctuation and survives.
- An explicit date in the text overrides the column or tab's implied day, because typing
  "tomorrow" is deliberate and the column is just where the cursor happened to be.
- 25 parser tests, plus an end-to-end check that parsed input produces a correctly dated,
  prioritised and filed reminder in EventKit.

## [Unreleased] — Widgets

### Added

- **Two widget kinds, spanning Home Screen and Lock Screen (and StandBy, which reuses the
  Lock Screen families for free):**
  - **Today** — systemSmall/Medium/Large plus accessoryCircular/Rectangular/Inline.
    Small shows the count with an overdue badge; medium/large show the actual list, with a
    real tap-to-complete checkbox on each row.
  - **Next Up** — the single next thing due, for the classic Lock Screen glance. Read-only
    across every size, including its Home Screen small: a bare checkbox with no other
    context isn't worth the tap it would save, so the whole widget opens the app to that
    task instead.
  - Lock Screen/StandBy widgets are read-only glances that deep-link into the app on tap
    (a new `reminderscompanion://` URL scheme); interactive completion lives only on the
    Home Screen `Today` widget's rows, where there's room for it to be a considered choice
    rather than a cramped one.
- **Tap-to-complete via `AppIntent`**, completing a reminder with no app launch. Calls
  `ReminderStore.completeReminder(externalID:in:)`, the same static function a diagnostic
  verifies end-to-end before trusting it — create a probe task, complete it through the
  intent's exact code path against a fresh `EKEventStore` (mirroring how an extension
  process actually runs, not the app's live store), and confirm from a third independent
  store that it persisted. Verified safe.
- Widgets reload immediately when backgrounding the app (catching every in-app edit with
  one hook) and when the completion intent itself fires — not fully live, since WidgetKit
  budgets background refreshes, but responsive to the moments that matter.

### Changed

- `WidgetDataProvider` (the widget's read path) and `WidgetKind` (shared kind
  identifiers) moved into `RemindersCore`, since neither has any WidgetKit dependency and
  both the extension and the app's own diagnostic need the identical logic — one source of
  truth rather than a widget-only copy nothing else could verify against.
- Extracted `ReminderStore.makeTaskItem`, the pure `EKReminder` → `TaskItem` mapping, out
  of the sidecar-aware fetch path so the widget (a separate, memory-constrained process
  with no reason to spin up SwiftData for information it never shows) can build the exact
  same shape from a bare `EKEventStore` fetch.

### Verified, not yet seen

- The completion intent's logic and the widget's data-fetch logic are proven against live
  EventKit data via a diagnostic launch hook, the same rigor as the recurring-completion
  check. **Actually placing a widget on a Home Screen or Lock Screen and tapping it is not
  something this session's tooling can automate** — that verification needs a person, the
  same way drag-to-reschedule ultimately did.

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
