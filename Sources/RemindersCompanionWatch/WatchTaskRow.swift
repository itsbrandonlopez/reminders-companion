import RemindersCore
import SwiftUI

struct WatchTaskRow: View {
    let task: TaskItem
    let onComplete: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Button(action: onComplete) {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundStyle(Color(task.listColor))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text(task.title)
                    .font(.body)
                    .lineLimit(2)
                HStack(spacing: 5) {
                    Text(task.listName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let time = task.dueTimeLabel {
                        Text(time)
                            .font(.caption2)
                            .foregroundStyle(task.isOverdue() ? .red : .secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

extension Color {
    init(_ rgba: RGBA) {
        self.init(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
    }
}
