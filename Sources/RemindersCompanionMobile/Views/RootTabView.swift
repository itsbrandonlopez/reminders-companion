import RemindersCore
import SwiftUI

/// Three tabs. Today and Week carry only dated work; the two piles that would clog them
/// live in Triage, one tap away and badged when the backlog is not empty.
struct RootTabView: View {
    @Environment(MobileEnvironment.self) private var env
    @State private var selection = 0

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
    }
}
