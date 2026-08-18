import RemindersCore
import SwiftUI

/// The week as a single vertical column: one section per day, tasks flat beneath it.
///
/// Not subdivided by list — on a phone that nesting costs more in scrolling than it
/// returns in structure. The list colour lives on each row instead.
struct WeekView: View {
    @Environment(MobileEnvironment.self) private var env

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                dayStrip
                Divider()
                list
            }
            .navigationTitle(weekLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { env.jumpWeek(-1) } label: { Image(systemName: "chevron.left") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { env.jumpWeek(1) } label: { Image(systemName: "chevron.right") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Today") { env.goToToday() }
                }
            }
        }
    }

    private var weekLabel: String {
        guard let first = env.week.first, let last = env.week.last else { return "Week" }
        return "\(first.monthDayLabel) – \(last.monthDayLabel)"
    }

    /// Always visible, and doubles as the drop target row.
    ///
    /// Dragging inside a long vertical list breaks the moment the target day scrolls off
    /// screen. Pinning the seven days to the top means every day is reachable without
    /// scrolling mid-drag, and it works as a jump control the rest of the time.
    private var dayStrip: some View {
        ScrollViewReader { proxy in
            HStack(spacing: 6) {
                ForEach(env.week, id: \.self) { day in
                    DayPill(day: day, count: env.tasks(on: day).count)
                        .onTapGesture { withAnimation { proxy.scrollTo(day, anchor: .top) } }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Palette.surface)
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14, pinnedViews: []) {
                    ForEach(env.week, id: \.self) { day in
                        DayBlock(day: day)
                            .id(day)
                    }
                }
                .padding(.vertical, 12)
            }
            .background(Palette.background)
            .refreshable { await env.store.refresh() }
            .onAppear {
                // Open on today rather than Monday — the week is for planning around now.
                if let today = env.week.first(where: \.isToday) {
                    proxy.scrollTo(today, anchor: .top)
                }
            }
        }
    }
}

/// One day, and the drop target for it.
///
/// The whole block accepts a drop — header, rows and the empty space beneath — so aiming
/// at a day is forgiving. A `List` `Section` cannot do this, which is why the week is a
/// `ScrollView` rather than a `List`.
private struct DayBlock: View {
    let day: Day
    @Environment(MobileEnvironment.self) private var env
    @State private var isTargeted = false

    private var tasks: [TaskItem] { env.tasks(on: day) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DaySectionHeader(day: day, summary: env.overlaySummary(on: day))
                .padding(.horizontal, 16)

            VStack(spacing: 0) {
                if tasks.isEmpty {
                    Text("Nothing planned")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 16)
                } else {
                    ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                        TaskRow(task: task, isDraggable: true)
                        if index < tasks.count - 1 {
                            Divider().padding(.leading, 46)
                        }
                    }
                }
            }
            .background(Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isTargeted ? Palette.accent : .clear, lineWidth: 2)
            )
            .padding(.horizontal, 12)
        }
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first,
                  let task = env.store.tasks.first(where: { $0.id == id }) else { return false }
            Task { await env.store.schedule(task, to: day) }
            return true
        } isTargeted: { isTargeted = $0 }
    }
}

private struct DayPill: View {
    let day: Day
    let count: Int
    @Environment(MobileEnvironment.self) private var env
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 2) {
            Text(day.shortWeekday.uppercased())
                .font(.system(size: 9, weight: .semibold))
            Text(day.dayNumber)
                .font(.system(size: 15, weight: day.isToday ? .bold : .regular))
            Circle()
                .fill(count > 0 ? Palette.accent : .clear)
                .frame(width: 4, height: 4)
        }
        .foregroundStyle(day.isToday ? Palette.accent : (day.isPast ? Palette.textTertiary : Palette.textPrimary))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isTargeted ? Palette.accent.opacity(0.22)
                      : (day.isToday ? Palette.accent.opacity(0.1) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(isTargeted ? Palette.accent : .clear, lineWidth: 1.5)
        )
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first,
                  let task = env.store.tasks.first(where: { $0.id == id }) else { return false }
            Task { await env.store.schedule(task, to: day) }
            return true
        } isTargeted: { isTargeted = $0 }
    }
}

private struct DaySectionHeader: View {
    let day: Day
    let summary: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(day.relativeName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(day.isToday ? Palette.accent : Palette.textPrimary)
                Text(day.monthDayLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textTertiary)
            }
            if let summary {
                Label(summary, systemImage: "calendar")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .textCase(nil)
        .padding(.vertical, 2)
    }
}

private extension Day {
    var dayNumber: String { String(day) }
}
