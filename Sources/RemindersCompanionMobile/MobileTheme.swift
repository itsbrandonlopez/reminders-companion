import RemindersCore
import SwiftUI
import UIKit

extension Color {
    init(_ rgba: RGBA) {
        self.init(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
    }

    /// Resolves per-appearance at draw time, so light/dark switching needs no
    /// `colorScheme` plumbed through every view.
    static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

private func hex(_ value: UInt32) -> UIColor {
    UIColor(
        red: Double((value >> 16) & 0xFF) / 255,
        green: Double((value >> 8) & 0xFF) / 255,
        blue: Double(value & 0xFF) / 255,
        alpha: 1
    )
}

/// The same palette as the Mac app, kept as its own file rather than shared.
///
/// The two apps want different metrics — a phone row is not a board card — and coupling
/// them through one theme would mean every spacing tweak on one platform is a decision
/// about the other.
enum Palette {
    static let background   = Color.dynamic(light: hex(0xF7F7F9), dark: hex(0x121417))
    static let surface      = Color.dynamic(light: hex(0xFFFFFF), dark: hex(0x1D2025))
    static let surfaceRaised = Color.dynamic(light: hex(0xFFFFFF), dark: hex(0x262A30))
    static let border       = Color.dynamic(light: hex(0xE4E4EA), dark: hex(0x32363D))

    static let textPrimary   = Color.dynamic(light: hex(0x1C1C1E), dark: hex(0xE9E9EB))
    static let textSecondary = Color.dynamic(light: hex(0x7C7C82), dark: hex(0x9598A0))
    static let textTertiary  = Color.dynamic(light: hex(0xB0B0B6), dark: hex(0x64676E))

    static let accent  = Color.dynamic(light: hex(0x3D7BE8), dark: hex(0x5C9BFF))
    static let overdue = Color.dynamic(light: hex(0xE05B4B), dark: hex(0xF2705F))
    static let flag    = Color.dynamic(light: hex(0xE8A33D), dark: hex(0xF0B152))
}

// `Day`'s labels now live in `RemindersCore.DateLabels`, shared with the Mac and the
// widgets. See the note in the Mac's Theme.swift.
