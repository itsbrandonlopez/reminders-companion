#if DEBUG
import RemindersCore
import SwiftUI

/// Launch-argument hooks used to drive the app headlessly on a Simulator.
///
/// Entirely absent from Release builds. They exist because a Simulator's Reminders
/// database starts empty and there is no way to script taps from this environment, so
/// verification has to be reachable from the launch command — but `--seed-demo` writes
/// real reminders into whatever account the app is pointed at, which has no business
/// being reachable in a shipping binary.
enum DebugHooks {

    /// True when a hook is present; lets the setup flow be skipped for automation.
    static var isSeedingDemo: Bool {
        CommandLine.arguments.contains("--seed-demo")
    }

    /// `--tab week|triage` opens straight to a tab. Returns nil in Release.
    static var requestedTab: Int? {
        guard let i = CommandLine.arguments.firstIndex(of: "--tab"),
              i + 1 < CommandLine.arguments.count else { return nil }
        switch CommandLine.arguments[i + 1] {
        case "week": return 1
        case "triage": return 2
        case "today": return 0
        default: return nil
        }
    }

    @MainActor
    static func runIfRequested(env: MobileEnvironment) async {
        guard env.store.access == .granted else { return }

        if CommandLine.arguments.contains("--test-recurring") {
            await write(await env.store.diagnoseRecurringCompletion(), to: "recurrence.txt")
        }
        if isSeedingDemo {
            if !env.store.hasSampleData { await env.store.installSampleData() }
            env.completeSetup()
        }
        if CommandLine.arguments.contains("--test-widget") {
            await write(await WidgetDiagnostic.run(env: env), to: "widget-diagnostic.txt")
        }
    }

    private static func write(_ report: String, to filename: String) async {
        let url = URL.documentsDirectory.appendingPathComponent(filename)
        try? report.write(to: url, atomically: true, encoding: .utf8)
    }
}
#endif
