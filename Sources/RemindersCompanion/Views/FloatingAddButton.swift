import RemindersCore
import SwiftUI

/// The circular + that floats over every board and every list.
///
/// One instance, mounted above the detail column in `ContentView`, for the same reason the
/// iPhone app keeps one above its `TabView`: three copies would be three positions, three
/// shadows and three chances to drift apart.
///
/// It does two things, and the second is the point. Clicking it opens a compose field in
/// whatever column the current view implies. *Dragging* it onto a column opens the field
/// there instead — which is how you say "new task, on Thursday" or "new task, in Errands"
/// without typing a date or a `#list` token. The gesture is the same one the cards already
/// use, so a day column already knows how to be a target.
struct FloatingAddButton: View {
    @Environment(AppEnvironment.self) private var env
    @State private var isHovering = false

    var body: some View {
        // Deliberately not a `Button`. A button's own press gesture competes with
        // `draggable` for the same mouse-down on macOS, and dragging is the half of this
        // control that has no other way to be expressed — clicking has ⌘N as well. So the
        // tap is a gesture too, and the button-ness is put back for VoiceOver by hand.
        Image(systemName: "plus")
            .font(.system(size: 21, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 46, height: 46)
            .background(Circle().fill(Palette.accent))
            .shadow(
                color: .black.opacity(isHovering ? 0.3 : 0.22),
                radius: isHovering ? 10 : 7,
                y: 3
            )
            .scaleEffect(isHovering ? 1.06 : 1)
            .contentShape(Circle())
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.14)) { isHovering = hovering }
            }
            .onTapGesture { env.beginCompose(env.defaultComposeTarget) }
            .draggable(DragPayload.newTask) {
                // The preview is the card about to be created, not a copy of the button,
                // so the gesture reads as placing a task rather than dragging a control.
                DragGhost()
            }
            .accessibilityElement()
            .accessibilityLabel("Add task")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { env.beginCompose(env.defaultComposeTarget) }
            .help("Add a task — or drag it onto a day or a list to add it there")
    }
}

/// What follows the cursor while the + is being dragged.
private struct DragGhost: View {
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Palette.accent)
            Text("New task")
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.textPrimary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(width: Metrics.columnWidth - 20, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Metrics.cardCorner, style: .continuous)
                .fill(Palette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.cardCorner, style: .continuous)
                .strokeBorder(Palette.accent.opacity(0.6), lineWidth: 1)
        )
    }
}
