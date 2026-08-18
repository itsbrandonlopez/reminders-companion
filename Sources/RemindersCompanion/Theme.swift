import AppKit
import RemindersCore
import SwiftUI

extension Color {
    init(_ rgba: RGBA) {
        self.init(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
    }

    /// Resolves per-appearance at draw time, so light/dark switching needs no
    /// `colorScheme` plumbed through every view — and follows the system live.
    static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

private func hex(_ value: UInt32) -> NSColor {
    NSColor(
        srgbRed: Double((value >> 16) & 0xFF) / 255,
        green: Double((value >> 8) & 0xFF) / 255,
        blue: Double(value & 0xFF) / 255,
        alpha: 1
    )
}

/// Palette modelled on Things 3: near-white in light mode, a desaturated blue-grey in
/// dark mode rather than black, separation carried by whitespace and hairlines instead
/// of shadows and heavy borders.
enum Palette {
    static let window       = Color.dynamic(light: hex(0xFFFFFF), dark: hex(0x1C1E22))
    static let sidebar      = Color.dynamic(light: hex(0xF2F1F6), dark: hex(0x16181B))
    static let column       = Color.dynamic(light: hex(0xF7F7F9), dark: hex(0x212429))
    static let card         = Color.dynamic(light: hex(0xFFFFFF), dark: hex(0x2A2D33))
    static let cardBorder   = Color.dynamic(light: hex(0xE4E4EA), dark: hex(0x34383F))
    static let separator    = Color.dynamic(light: hex(0xE8E8ED), dark: hex(0x2C2F35))

    static let textPrimary   = Color.dynamic(light: hex(0x2C2C2E), dark: hex(0xE9E9EB))
    static let textSecondary = Color.dynamic(light: hex(0x8A8A8F), dark: hex(0x8E9096))
    static let textTertiary  = Color.dynamic(light: hex(0xB4B4B9), dark: hex(0x63666C))

    /// Things' signature blue, used for today, selection and completion.
    static let accent  = Color.dynamic(light: hex(0x3D7BE8), dark: hex(0x4E8FF5))
    static let overdue = Color.dynamic(light: hex(0xE05B4B), dark: hex(0xF2705F))
    static let flag    = Color.dynamic(light: hex(0xE8A33D), dark: hex(0xF0B152))
}

enum Metrics {
    static let columnWidth: CGFloat = 240
    static let collapsedWidth: CGFloat = 44
    static let cardCorner: CGFloat = 7
    static let columnCorner: CGFloat = 12
    static let gutter: CGFloat = 12
}

/// Things uses a rounded square rather than a circle, and fills it with the list's own
/// colour on completion.
struct Checkbox: View {
    let isOn: Bool
    var tint: Color
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                .strokeBorder(isOn ? tint : (isHovering ? tint : Palette.textTertiary), lineWidth: 1.3)
                .background(
                    RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                        .fill(isOn ? tint : .clear)
                )
                .frame(width: 15, height: 15)
                .overlay {
                    if isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

extension Day {
    var weekdayName: String {
        let f = DateFormatter(); f.dateFormat = "EEE"
        return f.string(from: startOfDay())
    }

    var dayNumber: String { String(day) }
    var isToday: Bool { self == Day.today() }
    var isPast: Bool { self < Day.today() }

    var monthDayLabel: String {
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return f.string(from: startOfDay())
    }
}
