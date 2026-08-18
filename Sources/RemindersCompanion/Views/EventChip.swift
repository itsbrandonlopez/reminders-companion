import RemindersCore
import SwiftUI

/// A calendar event in a day column.
///
/// Deliberately shaped unlike a task card — tinted fill, no checkbox, a leading colour
/// bar — because these are commitments you cannot tick off. The point is to see at a
/// glance that Thursday is already spoken for.
struct EventChip: View {
    let event: CalendarEvent
    let day: Day

    private var tint: Color { Color(event.color) }

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(tint)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 1.5) {
                Text(event.title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(event.timeLabel(on: day))
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textSecondary)

                if let location = event.location {
                    Text(location)
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(tint.opacity(0.14))
        )
        .help(helpText)
    }

    private var helpText: String {
        var parts = [event.title, event.timeLabel(on: day), event.calendarName]
        if let location = event.location { parts.append(location) }
        return parts.joined(separator: "\n")
    }
}
