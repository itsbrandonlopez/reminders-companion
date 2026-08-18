import RemindersCore
import SwiftUI

/// Three tabs. Today and Week carry only dated work; the two piles that would clog them
/// live in Triage, one tap away and badged when the backlog is not empty.
struct RootTabView: View {
    @Environment(MobileEnvironment.self) private var env
    /// Test hook: `--tab week|triage` opens straight to a tab, so the views can be driven
    /// headlessly on a Simulator. Defaults to Today.
    @State private var selection = {
        guard let i = CommandLine.arguments.firstIndex(of: "--tab"),
              i + 1 < CommandLine.arguments.count else { return 0 }
        switch CommandLine.arguments[i + 1] {
        case "week": return 1
        case "triage": return 2
        default: return 0
        }
    }()

    var body: some View {
        TabView(selection: $selection) {
            TodayView(onShowTriage: { selection = 2 })
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(0)

            WeekView()
                .tabItem { Label("Week", systemImage: "calendar") }
                .tag(1)

            TriageView()
                .tabItem { Label("Triage", systemImage: "tray.full") }
                .badge(env.pastDueCount)
                .tag(2)
        }
        // A tapped widget sets `requestedTab`; consume it once, so returning to the app
        // later doesn't keep yanking the user back to Today.
        .onChange(of: env.requestedTab) { _, requested in
            guard let requested else { return }
            selection = requested
            env.requestedTab = nil
        }
    }
}
