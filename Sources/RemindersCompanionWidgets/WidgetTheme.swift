import RemindersCore
import SwiftUI

/// The same palette as the phone app, redeclared rather than shared.
///
/// A widget extension can't import the app target — only the shared `RemindersCore`
/// package — so this is copied, not linked. It's a handful of colors; the duplication is
/// cheaper than restructuring the app's theme into its own library just for this.
enum WidgetPalette {
    static let textPrimary   = Color(red: 0x1C/255, green: 0x1C/255, blue: 0x1E/255)
    static let textSecondary = Color(red: 0x7C/255, green: 0x7C/255, blue: 0x82/255)
    static let accent  = Color(red: 0x3D/255, green: 0x7B/255, blue: 0xE8/255)
    static let overdue = Color(red: 0xE0/255, green: 0x5B/255, blue: 0x4B/255)
    static let flag    = Color(red: 0xE8/255, green: 0xA3/255, blue: 0x3D/255)
}

extension Color {
    init(_ rgba: RGBA) {
        self.init(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
    }
}

extension Day {
    var relativeLabel: String {
        if self == .today() { return "Today" }
        if self == Day.today().adding(days: 1) { return "Tomorrow" }
        let f = DateFormatter(); f.dateFormat = "EEE"
        return f.string(from: startOfDay())
    }
}
