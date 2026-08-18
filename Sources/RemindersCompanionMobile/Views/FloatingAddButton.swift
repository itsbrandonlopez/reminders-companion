import SwiftUI

/// The circular + that floats over every tab.
///
/// Lives as a single overlay above the `TabView` rather than being repeated inside each
/// tab: one instance means one position, one shadow, and no chance of the three drifting
/// apart. It also sits outside every `NavigationStack`, so scrolling a list can never
/// clip or scroll it away.
struct FloatingAddButton: View {
    let action: () -> Void
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Circle().fill(Palette.accent))
                .shadow(color: .black.opacity(0.22), radius: 8, y: 4)
                .scaleEffect(isPressed ? 0.92 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add task")
        // The tap target is 56pt, comfortably past the 44pt minimum, so the press
        // animation is the only feedback that needs adding.
        .onLongPressGesture(minimumDuration: 0, pressing: { pressing in
            withAnimation(.easeOut(duration: 0.12)) { isPressed = pressing }
        }, perform: {})
    }
}
