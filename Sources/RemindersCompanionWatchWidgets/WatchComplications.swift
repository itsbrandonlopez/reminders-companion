import RemindersCore
import SwiftUI
import WidgetKit

/// Watch face complications.
///
/// Read-only by necessity — watchOS EventKit cannot write, and a complication is a glance
/// rather than a control surface. Tapping opens the watch app, where completing sends a
/// request to the iPhone.
struct WatchEntry: TimelineEntry {
    let date: Date
    let todayCount: Int
    let overdueCount: Int
    let next: TaskItem?
}

struct WatchProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchEntry {
        WatchEntry(date: .now, todayCount: 0, overdueCount: 0, next: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchEntry) -> Void) {
        let box = SendableCompletion(run: completion)
        Task { box.run(await currentEntry()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchEntry>) -> Void) {
        let box = SendableCompletion(run: completion)
        Task {
            let entry = await currentEntry()
            // "Today" turns over at midnight regardless of activity. Everything else is
            // driven by reloads from the app itself; watchOS budgets complication
            // refreshes even more tightly than iOS widgets, so the face can lag reality.
            let midnight = Calendar.current.nextDate(
                after: .now, matching: DateComponents(hour: 0, minute: 1),
                matchingPolicy: .nextTime
            ) ?? .now.addingTimeInterval(3600)
            box.run(Timeline(entries: [entry], policy: .after(midnight)))
        }
    }

    private func currentEntry() async -> WatchEntry {
        guard WidgetDataProvider.authorizationStatus() == .fullAccess else {
            return WatchEntry(date: .now, todayCount: 0, overdueCount: 0, next: nil)
        }
        return WatchEntry(
            date: .now,
            todayCount: await WidgetDataProvider.fetchToday().count,
            overdueCount: await WidgetDataProvider.overdueCount(),
            next: await WidgetDataProvider.fetchNext()
        )
    }
}

struct WatchTodayComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.watchToday, provider: WatchProvider()) { entry in
            WatchComplicationView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("How much is left today.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

struct WatchComplicationView: View {
    let entry: WatchEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("\(entry.todayCount) today")
                    .font(.headline)
                if let next = entry.next {
                    Text(next.title).font(.caption2).lineLimit(2)
                } else {
                    Text("All clear").font(.caption2)
                }
            }
        case .accessoryInline:
            Text(entry.todayCount == 0 ? "All clear" : "\(entry.todayCount) today")
        case .accessoryCorner:
            Text("\(entry.todayCount)")
                .font(.title2)
                .widgetLabel(entry.overdueCount > 0 ? "\(entry.overdueCount) overdue" : "today")
        default:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("\(entry.todayCount)").font(.title3.bold())
                    Text("today").font(.system(size: 9))
                }
            }
        }
    }
}

@main
struct WatchComplicationsBundle: WidgetBundle {
    var body: some Widget {
        WatchTodayComplication()
    }
}
