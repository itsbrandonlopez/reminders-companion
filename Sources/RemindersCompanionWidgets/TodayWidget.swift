import AppIntents
import RemindersCore
import SwiftUI
import WidgetKit

struct TodayEntry: TimelineEntry {
    let date: Date
    let tasks: [TaskItem]
    let overdueCount: Int
    let isAuthorized: Bool
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: .now, tasks: [], overdueCount: 0, isAuthorized: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        let box = SendableCompletion(run: completion)
        Task {
            box.run(await currentEntry())
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let box = SendableCompletion(run: completion)
        Task {
            let entry = await currentEntry()
            // "Today" changes meaning at midnight even with nothing else happening, so
            // that is the one reload point worth scheduling in advance. Everything else
            // — completing or rescheduling a task — reloads immediately via
            // `WidgetCenter.reloadTimelines`, called from both the app and the widget's
            // own completion intent.
            let midnight = Calendar.current.nextDate(
                after: .now, matching: DateComponents(hour: 0, minute: 1),
                matchingPolicy: .nextTime
            ) ?? .now.addingTimeInterval(3600)
            box.run(Timeline(entries: [entry], policy: .after(midnight)))
        }
    }

    private func currentEntry() async -> TodayEntry {
        guard WidgetDataProvider.authorizationStatus() == .fullAccess else {
            return TodayEntry(date: .now, tasks: [], overdueCount: 0, isAuthorized: false)
        }
        // One fetch for both numbers. `overdueCount` counts across *everything*, not just
        // today's tasks: filtering today's list for overdue items only ever finds tasks
        // explicitly re-planned for today that still carry a past deadline — usually none —
        // so the widget showed "0 overdue" beside a backlog of thirty, while the watch face
        // showed the real figure. Both surfaces now report the same number.
        let snapshot = await WidgetDataProvider.snapshot()
        return TodayEntry(
            date: .now, tasks: snapshot.today,
            overdueCount: snapshot.overdueCount, isAuthorized: true
        )
    }
}

struct TodayWidget: Widget {
    static let kind = WidgetKind.today

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("What's planned, due, or overdue today.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

struct TodayWidgetView: View {
    let entry: TodayEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if !entry.isAuthorized {
            disconnected
        } else {
            switch family {
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            case .accessoryInline: inline
            case .systemLarge: home(rows: 6)
            case .systemMedium: home(rows: 3)
            default: small
            }
        }
    }

    private var disconnected: some View {
        Link(destination: URL(string: "reminderscompanion://today")!) {
            VStack(spacing: 4) {
                Image(systemName: "checklist")
                Text("Open to connect")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Home Screen

    private var small: some View {
        Link(destination: URL(string: "reminderscompanion://today")!) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(WidgetPalette.accent)
                Spacer(minLength: 0)
                Text("\(entry.tasks.count)")
                    .font(.system(size: 30, weight: .bold))
                Text(entry.tasks.count == 1 ? "task today" : "tasks today")
                    .font(.caption2)
                    .foregroundStyle(WidgetPalette.textSecondary)
                if entry.overdueCount > 0 {
                    Label("\(entry.overdueCount) overdue", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(WidgetPalette.overdue)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func home(rows: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Today", systemImage: "sun.max.fill")
                    .font(.headline)
                    .foregroundStyle(WidgetPalette.accent)
                Spacer()
                if entry.overdueCount > 0 {
                    Text("\(entry.overdueCount) overdue")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(WidgetPalette.overdue)
                }
            }

            if entry.tasks.isEmpty {
                Spacer(minLength: 0)
                Text("Nothing planned")
                    .font(.caption)
                    .foregroundStyle(WidgetPalette.textSecondary)
                Spacer(minLength: 0)
            } else {
                ForEach(entry.tasks.prefix(rows)) { task in
                    TaskRowButton(task: task)
                }
                if entry.tasks.count > rows {
                    Text("+\(entry.tasks.count - rows) more")
                        .font(.caption2)
                        .foregroundStyle(WidgetPalette.textSecondary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Lock Screen / StandBy
    //
    // Read-only. A checkbox crammed into two lines of Lock Screen text is not how these
    // are meant to be used — the interaction model there is glance, then tap to open the
    // app, which is what `widgetURL` below does.

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Text("\(entry.tasks.count)")
                    .font(.system(size: 20, weight: .bold))
                Text("today")
                    .font(.system(size: 9))
            }
        }
        .widgetURL(URL(string: "reminderscompanion://today"))
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(entry.tasks.count) task\(entry.tasks.count == 1 ? "" : "s") today")
                .font(.headline)
            if let first = entry.tasks.first {
                Text(first.title).font(.caption).lineLimit(1)
            } else {
                Text("Nothing planned").font(.caption)
            }
        }
        .widgetURL(URL(string: "reminderscompanion://today"))
    }

    private var inline: some View {
        Text(entry.tasks.isEmpty
             ? "Nothing planned today"
             : "\(entry.tasks.count) task\(entry.tasks.count == 1 ? "" : "s") today")
            .widgetURL(URL(string: "reminderscompanion://today"))
    }
}

/// One row on a Home Screen widget: title plus a real, tappable completion button.
///
/// `Button(intent:)` runs `CompleteTaskIntent` directly from the extension process — no
/// app launch, no leaving the Lock Screen or Home Screen.
struct TaskRowButton: View {
    let task: TaskItem

    var body: some View {
        HStack(spacing: 7) {
            Button(intent: CompleteTaskIntent(taskID: task.id)) {
                Image(systemName: "circle")
                    .foregroundStyle(Color(task.listColor))
            }
            .buttonStyle(.plain)

            Text(task.title)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(WidgetPalette.textPrimary)

            Spacer(minLength: 0)

            if let time = task.dueTimeLabel {
                Text(time)
                    .font(.caption2)
                    .foregroundStyle(task.isOverdue() ? WidgetPalette.overdue : WidgetPalette.textSecondary)
            }
        }
    }
}
