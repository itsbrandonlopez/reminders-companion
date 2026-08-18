#if DEBUG
import AppKit
import RemindersCore
import SwiftUI

/// Launch-argument hooks for driving the Mac app during development.
/// Absent from Release builds — `--selftest` creates and deletes real reminders.
enum DebugHooks {

    /// `--appearance light|dark` overrides this app only, leaving the system setting
    /// alone. Used for checking both themes without touching the machine's appearance.
    @MainActor
    static func applyAppearanceOverride() {
        guard let index = CommandLine.arguments.firstIndex(of: "--appearance"),
              index + 1 < CommandLine.arguments.count else { return }
        switch CommandLine.arguments[index + 1] {
        case "light": NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case "dark": NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
    }

    /// `--selftest` exercises the full write path against a scratch list and writes the
    /// result next to the built app.
    @MainActor
    static func runSelfTestIfRequested(env: AppEnvironment) async {
        guard CommandLine.arguments.contains("--selftest") else { return }
        while env.store.access == .notDetermined || env.store.access == .unknown {
            try? await Task.sleep(for: .milliseconds(200))
        }
        let report = await SelfTest.run(env.store)
        let url = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Desktop/Gigs/RemindersCompanion/build/selftest.txt")
        try? report.write(to: url, atomically: true, encoding: .utf8)
    }
}
#endif
