import RemindersCore
import SwiftUI

/// A transient "that just happened — undo?" bar.
///
/// Sits above the tab bar and auto-dismisses, because on a phone an undo affordance that
/// lingers becomes permanent furniture. Six seconds is long enough to catch a mis-drop and
/// short enough not to sit over a task row.
struct UndoBanner: View {
    let action: UndoableAction
    let onUndo: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .font(.system(size: 15))
            VStack(alignment: .leading, spacing: 1) {
                Text(action.label)
                    .font(.system(size: 13, weight: .medium))
                Text(action.task.title)
                    .font(.system(size: 12))
                    .opacity(0.75)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button("Undo", action: onUndo)
                .font(.system(size: 14, weight: .semibold))
                .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(
            Capsule().fill(Palette.accent)
                .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
        )
        .padding(.horizontal, 16)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .task {
            try? await Task.sleep(for: .seconds(6))
            onDismiss()
        }
    }
}
