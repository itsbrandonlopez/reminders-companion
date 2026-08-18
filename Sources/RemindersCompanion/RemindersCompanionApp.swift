import AppKit
import RemindersCore
import SwiftUI

@main
struct RemindersCompanionApp: App {
    @State private var env = AppEnvironment()

    var body: some Scene {
        WindowGroup("Reminders Companion") {
            ContentView()
                .environment(env)
                .frame(minWidth: 900, minHeight: 560)
                .onAppear {
                    // `--appearance light|dark` overrides this app only, leaving the
                    // system setting alone. Used for checking both themes.
                    guard let index = CommandLine.arguments.firstIndex(of: "--appearance"),
                          index + 1 < CommandLine.arguments.count else { return }
                    switch CommandLine.arguments[index + 1] {
                    case "light": NSApplication.shared.appearance = NSAppearance(named: .aqua)
                    case "dark": NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
                    default: break
                    }
                }
                .task {
                    // Hidden diagnostic: `--selftest` exercises the write path against a
                    // scratch list and writes the result next to the app bundle.
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
        .defaultSize(width: 1500, height: 900)
        .commands {
            CommandGroup(after: .sidebar) {
                Button("Previous Week") { env.jumpWeek(-1) }
                    .keyboardShortcut("[", modifiers: .command)
                Button("Next Week") { env.jumpWeek(1) }
                    .keyboardShortcut("]", modifiers: .command)
                Button("This Week") { env.goToToday() }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                Divider()
                Button("Refresh") { Task { await env.store.refresh() } }
                    .keyboardShortcut("r", modifiers: .command)
            }
            CommandGroup(replacing: .help) {
                // For anyone trying the app against a Reminders account that has nothing
                // interesting in it yet.
                if env.store.hasSampleData {
                    Button("Remove Demo Tasks…") { env.pendingSampleAction = .remove }
                } else {
                    Button("Add Demo Tasks…") { env.pendingSampleAction = .install }
                }
            }
        }
    }
}
