import RemindersCore
import SwiftUI
import WidgetKit

struct NextUpEntry: TimelineEntry {
    let date: Date
    let task: TaskItem?
    let isAuthorized: Bool
}

struct NextUpProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextUpEntry {
        NextUpEntry(date: .now, task: nil, isAuthorized: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (NextUpEntry) -> Void) {
        let box = SendableCompletion(run: completion)
        Task { box.run(await currentEntry()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextUpEntry>) -> Void) {
        let box = SendableCompletion(run: completion)
        Task {
            let entry = await currentEntry()
            let midnight = Calendar.current.nextDate(
                after: .now, matching: DateComponents(hour: 0, minute: 1),
                matchingPolicy: .nextTime
            ) ?? .now.addingTimeInterval(3600)
            box.run(Timeline(entries: [entry], policy: .after(midnight)))
        }
    }

    private func currentEntry() async -> NextUpEntry {
        guard WidgetDataProvider.authorizationStatus() == .fullAccess else {
            return NextUpEntry(date: .now, task: nil, isAuthorized: false)
        }
        return NextUpEntry(date: .now, task: await WidgetDataProvider.fetchNext(), isAuthorized: true)
    }
}

/// A single fact, not a list: the next thing due. Distinct in purpose from "Today" — this
/// is the classic Lock Screen glance ("what's the very next thing"), not a summary of the
/// whole day, which is why it's its own widget kind rather than another size of the first.
struct NextUpWidget: Widget {
    static let kind = WidgetKind.nextUp

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: NextUpProvider()) { entry in
            NextUpWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Next Up")
        .description("The next thing on your list.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct NextUpWidgetView: View {
    let entry: NextUpEntry
    @Environment(\.widgetFamily) private var family

    private var deepLink: URL {
        URL(string: entry.task.map { "reminderscompanion://task/\($0.id)" } ?? "reminderscompanion://today")!
    }

    var body: some View {
        if !entry.isAuthorized {
            Link(destination: URL(string: "reminderscompanion://today")!) {
                Image(systemName: "checklist")
            }
        } else if let task = entry.task {
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "arrow.forward.circle.fill")
                }
                .widgetURL(deepLink)
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text("Next Up").font(.caption2).foregroundStyle(.secondary)
                    Text(task.title).font(.headline).lineLimit(2)
                    if let day = task.boardDay {
                        Text(day.relativeLabel + (task.dueTimeLabel.map { " · \($0)" } ?? ""))
                            .font(.caption2)
                    }
                }
                .widgetURL(deepLink)
            case .accessoryInline:
                Text("Next: \(task.title)").widgetURL(deepLink)
            default:
                Link(destination: deepLink) {
                    VStack(alignment: .leading, spacing: 6) {
                        Circle().fill(Color(task.listColor)).frame(width: 10, height: 10)
                        Spacer(minLength: 0)
                        Text(task.title)
                            .font(.headline)
                            .lineLimit(3)
                            .foregroundStyle(WidgetPalette.textPrimary)
                        if let day = task.boardDay {
                            Text(day.relativeLabel + (task.dueTimeLabel.map { " · \($0)" } ?? ""))
                                .font(.caption2)
                                .foregroundStyle(task.isOverdue() ? WidgetPalette.overdue : WidgetPalette.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        Group {
            switch family {
            case .accessoryInline:
                Text("Nothing up next")
            case .accessoryCircular:
                ZStack { AccessoryWidgetBackground(); Image(systemName: "checkmark") }
            default:
                VStack(spacing: 4) {
                    Image(systemName: "checkmark.circle").foregroundStyle(WidgetPalette.accent)
                    Text("All clear").font(.caption2).foregroundStyle(WidgetPalette.textSecondary)
                }
            }
        }
        .widgetURL(URL(string: "reminderscompanion://today"))
    }
}
