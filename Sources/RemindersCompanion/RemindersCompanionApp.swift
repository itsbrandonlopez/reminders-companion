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
                    #if DEBUG
                    DebugHooks.applyAppearanceOverride()
                    #endif
                }
                .task {
                    #if DEBUG
                    await DebugHooks.runSelfTestIfRequested(env: env)
                    #endif
                }
        }
        .defaultSize(width: 1500, height: 900)
        .commands {
            CommandGroup(replacing: .undoRedo) {
                Button("Undo \(env.store.undoable?.label ?? "")") {
                    Task { await env.store.undoLast() }
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(env.store.undoable == nil)
            }
            CommandGroup(replacing: .newItem) {
                // Opens the same field the floating + does, in the column the current
                // view implies.
                Button("New Task") { env.beginCompose(env.defaultComposeTarget) }
                    .keyboardShortcut("n", modifiers: .command)
            }
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
                Divider()
                Button("Run Setup Again…") { env.restartSetup() }
            }
        }
    }
}
