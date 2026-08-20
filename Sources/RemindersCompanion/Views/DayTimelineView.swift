import RemindersCore
import SwiftUI

/// Today's calendar as a vertical timeline, pinned to the side of the Today board.
///
/// It replaced a horizontal row of event chips across the top. That row gave every event
/// the same weight and the same size regardless of whether it was ten minutes or six
/// hours, and it pushed the actual work — the thing this app is for — down the screen. A
/// timeline answers the question the events are there to answer, which is not "what is on
/// today" but "what is left of today", and it answers it in the one dimension a list
/// cannot: proportion. A four-hour gig looks like four hours.
///
/// All-day events sit above the grid as one-line mentions. They have no position and no
/// duration, so drawing them as blocks would mean inventing both.
///
/// Strictly read-only, like the rest of the overlay. Nothing here can create, move or
/// delete an event.
struct DayTimelineView: View {
    let day: Day
    let events: [CalendarEvent]

    @Environment(AppEnvironment.self) private var env

    /// One hour of clock time, in points. Sized so a 30-minute meeting still has room for
    /// a title on one line.
    private static let hourHeight: CGFloat = 46
    private static let railWidth: CGFloat = 168
    private static let gutter: CGFloat = 34

    private var allDay: [CalendarEvent] { events.filter(\.isAllDay) }
    private var timed: [CalendarEvent] {
        events.filter { !$0.isAllDay }.sorted { $0.start < $1.start }
    }

    var body: some View {
        if env.isTimelineCollapsed {
            collapsed
        } else {
            expanded
        }
    }

    // MARK: - Expanded

    private var expanded: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !allDay.isEmpty {
                mentions
                Divider().overlay(Palette.separator)
            }
            grid
        }
        .frame(width: Self.railWidth)
        .background(Palette.window)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("SCHEDULE")
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Palette.textSecondary)
            Spacer()
            if let booked = bookedLabel {
                Text(booked)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .monospacedDigit()
            }
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { env.isTimelineCollapsed = true }
            } label: {
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.textSecondary)
            .help("Hide the timeline")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    /// All-day events, as the short mentions they are. No block, no position — an all-day
    /// event occupies the whole day or none of it, and a bar spanning every hour would say
    /// the day was full when it is not.
    private var mentions: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(allDay) { event in
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(event.color))
                        .frame(width: 5, height: 5)
                    Text(event.title)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .help("\(event.title)\nAll day · \(event.calendarName)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 9)
    }

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    hourLines
                    ForEach(placements, id: \.event.id) { placement in
                        block(for: placement)
                    }
                    if day.isToday, let offset = offset(for: Date()) {
                        nowLine.offset(y: offset)
                    }
                }
                .frame(height: CGFloat(windowHours) * Self.hourHeight, alignment: .top)
                .padding(.top, 6)
                // Clears the floating + so the last hour is never stuck under it.
                .padding(.bottom, 76)
            }
            .onAppear {
                // Opens an hour before now rather than at the top of the window, so a
                // long day does not open on hours already spent. The hour rows carry the
                // ids: an `.offset` anchor would not work, since offset moves what is
                // drawn without moving where the scroll view thinks it is.
                guard day.isToday else { return }
                proxy.scrollTo(max(windowStart, hour(of: Date()) - 1), anchor: .top)
            }
        }
    }

    private var hourLines: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(windowStart..<windowEnd, id: \.self) { hour in
                HStack(alignment: .top, spacing: 0) {
                    Text(hourLabel(hour))
                        .font(.system(size: 9.5))
                        .foregroundStyle(Palette.textTertiary)
                        .monospacedDigit()
                        .frame(width: Self.gutter - 6, alignment: .trailing)
                        .offset(y: -5)
                    Rectangle()
                        .fill(Palette.separator)
                        .frame(height: 1)
                        .padding(.leading, 6)
                }
                .frame(height: Self.hourHeight, alignment: .top)
                .id(hour)
            }
        }
    }

    private func block(for placement: Placement) -> some View {
        let event = placement.event
        let tint = Color(event.color)
        let laneWidth = (Self.railWidth - Self.gutter - 12) / CGFloat(placement.lanes)
        return VStack(alignment: .leading, spacing: 1) {
            Text(event.title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(placement.height > 34 ? 2 : 1)
            if placement.height > 30 {
                Text(event.timeLabel(on: day))
                    .font(.system(size: 9.5))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 5)
        .frame(width: laneWidth - 3, height: placement.height, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(tint.opacity(0.16))
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(tint)
                .frame(width: 2.5)
                .padding(.vertical, 1)
        }
        .offset(
            x: Self.gutter + CGFloat(placement.lane) * laneWidth,
            y: placement.offset
        )
        .help(helpText(for: event))
    }

    private var nowLine: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(Palette.overdue)
                .frame(width: 5, height: 5)
            Rectangle()
                .fill(Palette.overdue)
                .frame(height: 1)
        }
        .padding(.leading, Self.gutter - 2.5)
        .allowsHitTesting(false)
    }

    // MARK: - Collapsed

    private var collapsed: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { env.isTimelineCollapsed = false }
        } label: {
            VStack(spacing: 10) {
                Image(systemName: "chevron.left").font(.system(size: 9, weight: .bold))
                Image(systemName: "clock").font(.system(size: 11))
                Text("SCHEDULE")
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.6)
                    .fixedSize()
                    .rotationEffect(.degrees(90))
                    .frame(height: 86)
                if !events.isEmpty {
                    Text("\(events.count)")
                        .font(.system(size: 10.5))
                        .monospacedDigit()
                }
                Spacer()
            }
            .foregroundStyle(Palette.textSecondary)
            .padding(.vertical, 12)
            .frame(width: Metrics.collapsedWidth)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Palette.window)
        }
        .buttonStyle(.plain)
        .help("Show today's timeline")
    }

    // MARK: - Geometry

    /// Where a block sits and how tall it is, plus which of a set of overlapping events
    /// it is, so two meetings at the same hour sit side by side instead of on top of one
    /// another.
    private struct Placement {
        let event: CalendarEvent
        let offset: CGFloat
        let height: CGFloat
        let lane: Int
        let lanes: Int
    }

    /// The hours the grid actually draws.
    ///
    /// Not a full 24: a day with one 2pm meeting would be mostly empty grid. It spans the
    /// working day, stretched to cover whatever the events and the current time need, so
    /// nothing is ever cropped out of view.
    private var window: (start: Int, end: Int) {
        var start = 8
        var end = 19
        for event in timed {
            start = min(start, hour(of: event.start))
            // An event ending at 17:00 needs the 17 line drawn beneath it, not cropped.
            end = max(end, hour(of: event.end) + (minute(of: event.end) > 0 ? 1 : 0))
        }
        if day.isToday {
            let now = hour(of: Date())
            start = min(start, now)
            end = max(end, now + 1)
        }
        return (max(0, start), min(24, max(end, start + 1)))
    }

    private var windowStart: Int { window.start }
    private var windowEnd: Int { window.end }
    private var windowHours: Int { windowEnd - windowStart }

    /// Points from the top of the grid for a moment in time. Nil when it falls outside the
    /// drawn window entirely.
    private func offset(for date: Date) -> CGFloat? {
        let minutes = Double(hour(of: date) * 60 + minute(of: date))
        let windowTop = Double(windowStart * 60)
        let windowBottom = Double(windowEnd * 60)
        guard minutes >= windowTop, minutes <= windowBottom else { return nil }
        // Measured inside the `ZStack`, whose top padding shifts the gridlines and the
        // blocks together — adding it again here would float every block below its hour.
        return CGFloat((minutes - windowTop) / 60) * Self.hourHeight
    }

    private var placements: [Placement] {
        var out: [Placement] = []
        // Events are laid out per cluster of overlapping ones: a cluster of three splits
        // the width three ways, while an event alone at 4pm keeps the full width.
        for cluster in clusters {
            var laneEnds: [Date] = []
            var lanes: [Int] = []
            for event in cluster {
                if let free = laneEnds.firstIndex(where: { $0 <= event.start }) {
                    laneEnds[free] = event.end
                    lanes.append(free)
                } else {
                    laneEnds.append(event.end)
                    lanes.append(laneEnds.count - 1)
                }
            }
            for (event, lane) in zip(cluster, lanes) {
                // Clamped to the window: an event that started yesterday evening and runs
                // into this morning is drawn from the top of the grid, not off it.
                let top = offset(for: event.start) ?? 0
                let bottom = offset(for: event.end) ?? (CGFloat(windowHours) * Self.hourHeight)
                out.append(
                    Placement(
                        event: event,
                        offset: top,
                        // A fifteen-minute call still needs to be readable and clickable.
                        height: max(20, bottom - top - 2),
                        lane: lane,
                        lanes: laneEnds.count
                    )
                )
            }
        }
        return out
    }

    /// Runs of events that overlap each other, so lane splitting is local rather than
    /// applied to the whole day — one busy hour should not narrow every other block.
    private var clusters: [[CalendarEvent]] {
        var out: [[CalendarEvent]] = []
        var current: [CalendarEvent] = []
        var clusterEnd: Date?

        for event in timed {
            if let end = clusterEnd, event.start < end {
                current.append(event)
                clusterEnd = max(end, event.end)
            } else {
                if !current.isEmpty { out.append(current) }
                current = [event]
                clusterEnd = event.end
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    private var bookedLabel: String? {
        let minutes = timed.reduce(0) { $0 + $1.durationMinutes }
        guard minutes > 0 else { return nil }
        return minutes >= 60 ? String(format: "%.1fh", Double(minutes) / 60) : "\(minutes)m"
    }

    private func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.year = day.year
        components.month = day.month
        components.day = day.day
        components.hour = hour
        guard let date = Calendar.current.date(from: components) else { return "" }
        return DateLabels.hour.string(from: date)
    }

    private func helpText(for event: CalendarEvent) -> String {
        var parts = [event.title, event.timeLabel(on: day), event.calendarName]
        if let location = event.location { parts.append(location) }
        return parts.joined(separator: "\n")
    }

    private func hour(of date: Date) -> Int { Calendar.current.component(.hour, from: date) }
    private func minute(of date: Date) -> Int { Calendar.current.component(.minute, from: date) }
}
