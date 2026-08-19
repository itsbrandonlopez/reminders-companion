# Phase 0 — Round-trip spike findings

Run against a live iCloud Reminders account on macOS 26.5 / Xcode 26.6.
Reproduce with `spike/build.sh` then `open -a Probe.app --args read|write|alarm|timed|cleanup`.

## Test account shape

| | |
|---|---|
| Lists | 11, all iCloud, all writable |
| Incomplete tasks | 53 |
| Undated | 28 |
| Already using a start date | **0** |
| Using priority | **0** |
| Carrying alarms | 3 (the timed recurring ones) |

Nothing used `startDateComponents`, so claiming it as the planned day collides with
nothing. Several lists were client-shaped, which is what the Today board's kanban columns
are built around.

## Verdicts

| Question | Answer |
|---|---|
| Does a start date written via EventKit persist? | ✓ yes, verified from a fresh `EKEventStore` |
| Start + due as a multi-day span? | ✓ yes |
| Is `calendarItemExternalIdentifier` stable? | ✓ yes — and for iCloud it equals `calendarItemIdentifier` |
| Does writing dates auto-create a notification? | ✓ no — alarms are only ever what we put there |
| Does priority persist? | ✓ yes (1 = high) |
| Do alarms survive repeated rescheduling? | ✓ yes, unchanged after 3 moves |

## The one real trap

**`allDay` is a property of the reminder, not of each date.** Writing an all-day
`startDateComponents` (no hour/minute/second) coerces the *whole item* to all-day and
silently strips the time off a timed due date:

```
before → due: 2026-08-20 09:00:00 tz=America/New_York
after  → due: 2026-08-20 (all-day) tz=nil/floating      ← 09:00 lost
```

The alarm still fired correctly (it holds an absolute date), so notifications were never
at risk — but the due date visibly degrades in Reminders.app, which is unacceptable for a
bill.

**Fix, verified:** mirror the due date's timed-ness onto the start date. If the due date
carries a time, write a *timed* start (00:00:00 in the due date's own timezone); if the due
date is all-day or absent, write an all-day floating start.

```
seeded → due: 2026-08-20 09:00:00 tz=America/New_York
after  → due: 2026-08-20 09:00:00 tz=America/New_York   ← preserved
         start: 2026-08-19 00:00:00 tz=America/New_York
```

This rule lives in `Scheduling.plannedComponents(for:alongside:)` and is covered by unit tests.

## Other behaviours worth knowing

- A start date written all-day reads back as `00:00:00` rather than as a bare y/m/d, so
  day-bucketing must compare y/m/d and ignore any time component.
- Date components must use `NSCalendarIdentifierGregorian` or EventKit raises.
- `predicateForIncompleteReminders` with a **bounded** range silently drops undated items.
  Passing `nil`/`nil` returns everything incomplete, so the app fetches once and partitions
  in memory — that is how the backlog gets populated.
- Existing all-day due dates use a floating (`nil`) timezone; timed ones carry
  `America/New_York`. Matching that convention keeps our writes indistinguishable from
  Reminders' own.

## Environment notes

- TCC will **not** prompt for a bare command-line tool. It needs a bundled, signed `.app`,
  which is why the probe is one.
- There is no code-signing identity on this machine (`security find-identity` → 0 valid).
  Ad-hoc signatures are identified by cdhash, so **every rebuild looks like a new app to TCC
  and re-prompts for Reminders access.** Expected during development; a stable self-signed
  certificate would remove it if it becomes tiresome.

## Cleanup

The spike created an iCloud list named **RC Probe** holding three test reminders.
Remove it with `open -a Probe.app --args cleanup` (or delete it in Reminders.app).
