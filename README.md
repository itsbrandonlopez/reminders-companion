<div align="center">

# Reminders Companion

**Apple Reminders is where your tasks belong. It just isn't where you plan them.**

A macOS planning board that reads and writes your real Reminders — so Siri capture keeps
working, your notifications keep firing, and nothing gets copied into yet another silo.

</div>

---

## The problem

You keep tasks in Reminders for good reasons. It's baked into every Apple device, you can
capture with your voice from anywhere, and its notifications are the ones you actually
trust for things like paying a bill.

But Reminders shows you a list. Planning a week needs a board.

So you end up with a second app for planning — and now the thing you trust and the thing
you plan in are two different places, permanently out of sync.

**Reminders Companion is the board, on top of the tasks you already have.** There is no
import, no sync, no account. It reads your Reminders and writes back to them.

---

## What it does

### Plan your week by dragging

Seven day columns and an **Unscheduled** pool on the left. Drag a task onto Thursday and
it's planned for Thursday. Drag it back and it isn't.

The important part: dropping a card writes only the reminder's **start date**. Your due
date — the real deadline — is never touched. So "I'll do this Thursday" and "this is due
Friday" are finally two different facts, and you can see both at once.

### Multi-day work looks like multi-day work

Grab a card's edge and drag it across days. The task becomes a span, rendered as a bar
across the days it covers, with faded continuation chips so it never disappears from the
days in between.

### A Today board shaped like your clients

One kanban column per Reminders list. Your client lists become lanes, so "what's on for
this client today" is a glance, not a filter.

### Your lists, as lists

Clicking a list in the sidebar opens that list — everything in it, dated or not, in your
own order, the way Reminders shows it. It used to open the week board narrowed to that
list, which answered a much smaller question and hid every undated task in it.

Above them sit two tiles: **Today** and **Week**. Those are the two boards, and they are
the only views that aggregate across lists.

Give a list **sections** and it becomes a board of columns — the same Kanban view Reminders
shows for a sectioned list, and they follow you to the phone as headings. Drag cards between columns to file them. The sections are typed
here rather than read, because no app can read Reminders' own (see the limitations below),
so you name them once to match and they line up. Delete the last one and the list goes back
to being a list.

### A backlog that means something

Not "everything overdue" — everything that slipped past the *whole* week. Something due
Monday when it's Tuesday stays on Monday, where the week in progress can still absorb it.
Only genuinely stale work falls out into Backlog, sorted oldest-first so the thing quietly
rotting is on top.

### See your gigs behind your plans

Tick your Work calendar and its events draw at the top of each day, with booked hours
badged on the day header. "Can I take this on Thursday?" stops being a guess.

On the Today board the same events become a **vertical timeline** down the side, drawn to
scale with a now-line, so a four-hour gig looks like four hours and you can see what is
left of the day rather than just what is on it. All-day events sit above it as one-line
mentions — they have no position and no duration, and drawing them as blocks would mean
inventing both. Fold it away with the chevron if you want the room.

Read-only. The overlay never creates, edits, or deletes an event.

### Everything the task actually holds

Hover any card and open its details: notes, the exact deadline, planned day, priority,
list and estimate — all editable in place. Alarms and repeat rules are shown but left
read-only, because those are the parts you need to be able to trust.

### One + that goes where you drop it

A single button floating in the bottom-right corner. Click it and a field opens in the
column the current view implies — today, on the week; the list you're looking at, in a
list. **Drag it onto Thursday and the field opens on Thursday.** Drop it on a client
column and the task is filed there.

Which means "new task, on Thursday, for this client" needs no date typed and no list
picked. Nine permanent add fields, one per column, became one button.

### Built to disappear

Light and dark themes that follow your system live. Folders, manual ordering, and time
estimates for the things Reminders has nowhere to put.

---

## What it will never do

- **Never touch your alarms.** EventKit doesn't create them on its own, and this app
  doesn't modify them. Rescheduling a bill cannot change when — or whether — it notifies
  you.
- **Never write a due date behind your back.** The only path that sets a deadline is you
  dragging a span's far end, and even then it will only ever move it later.
- **Never become the source of truth.** Delete this app tomorrow and every task, list,
  date and reminder is exactly where you left it, on every device.

---

## Honest limitations

Some of what Reminders shows you simply isn't available to any third-party app. Verified
against the macOS SDK, not assumed:

| | |
|---|---|
| **Tags, flags, subtasks** | Absent from EventKit entirely. Cannot be read or written by anyone. |
| **Folders and list sections** | Not exposed either — "section" appears nowhere in EventKit's headers, Reminders' AppleScript declares only account, list and reminder, and its private store is TCC-protected. Both are recreated in-app, not mirrored: you type the names once and they line up by eye. |
| **Repeating reminders** | Verified safe. Completing one through this app rolls the series forward to the next occurrence with its recurrence rule intact, exactly as Reminders' own UI does. |

The full investigation, including the trap that shaped the whole date model, is in
[`spike/FINDINGS.md`](spike/FINDINGS.md).

---

## Trying it out

On first launch a short setup walks you through it: what the app does with your data,
connecting your reminders, choosing which lists you want to plan with, and optionally
overlaying your calendar. Each permission is asked for only after you've seen why, and
calendar access can be skipped entirely.

If your Reminders account is sparse, setup offers a set of demo tasks — available any time
from **Help → Add Demo Tasks**. It creates a separate list called *Companion Demo* holding
a dozen examples that cover every part of the board: an unscheduled pool, a multi-day span,
a backlog item, priorities, and one timed reminder with a real alarm, so you can watch
rescheduling leave it untouched.

Your own lists are never modified to make room for it, and **Help → Remove Demo Tasks**
deletes the demo list and nothing else.

## Requirements

macOS 14 or later. Xcode 16 or later to build.

## Build and run

```bash
git clone https://github.com/itsbrandonlopez/reminders-companion.git
cd reminders-companion
./make.sh && open build/RemindersCompanion.app
```

Build it on your own machine rather than passing the `.app` around — an ad-hoc signed app
copied from another Mac gets quarantined by Gatekeeper and won't open.

```bash
swift test
```

> Built without a code-signing certificate, macOS will re-ask for Reminders access on every
> rebuild — it identifies ad-hoc signed apps by hash. Normal during development.

### Syncing your arrangement

Manual order, estimates, folders and sections are the things Reminders has nowhere to put,
so they live in a small local database. That database can sync through iCloud, which is
what carries your sections to your phone — but iCloud containers need an enrolled Apple
Developer account, and an ad-hoc signed build cannot carry the entitlement.

Until then everything works, on this Mac, and the sidebar says so. To switch it on:

1. Create a CloudKit container called `iCloud.com.brandonlopez.RemindersCompanion` in
   [the developer portal](https://developer.apple.com/account/resources/identifiers/list).
2. Build signed, rather than ad-hoc:

```bash
export CODESIGN_IDENTITY="Apple Development: you@example.com (ABCDE12345)"
./make.sh && open build/RemindersCompanion.app
```

For the phone, set the team and the entitlements before generating the project:

```bash
export DEVELOPMENT_TEAM=ABCDE12345
export MOBILE_ENTITLEMENTS=signing/RemindersCompanionMobile.entitlements
xcodegen generate
```

Your tasks never depended on any of this — they sync through Reminders, as they always
have.

## How it's put together

One core, four surfaces — nothing carries its own copy of the domain logic.

- **`Sources/RemindersCore`** — no UI, 152 unit tests, builds for macOS, iOS and watchOS.
  `ReminderStore` is the only type that touches EventKit; `Scheduling` owns every date
  conversion; `QuickAddParser`, `Ranking` and the SwiftData sidecar live here too.
- **`Sources/RemindersCompanion`** — the Mac app: week board, kanban Today, folders,
  calendar overlay.
- **`Sources/RemindersCompanionMobile`** — the iPhone companion, plus
  **`…Widgets`** for Home and Lock Screen.
- **`Sources/RemindersCompanionWatch`** and **`…WatchWidgets`** — the Watch app and its
  complications.
- **`Sources/RemindersShared`** — the WatchConnectivity bridge, iOS and watchOS only, so
  the Mac never links a framework it has no use for.
- **`spike/`** — the throwaway probe that answered what Reminders can actually do, and the
  findings that came out of it.

The full architecture — all four surfaces, what each platform permits, and the invariants
that keep them consistent — is in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).
Changes are in [`CHANGELOG.md`](CHANGELOG.md).

---

<div align="center">
<sub>Your tasks stay in Reminders. This is just a better way to look at them.</sub>
</div>
