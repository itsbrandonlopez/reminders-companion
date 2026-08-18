import RemindersCore
import SwiftUI

/// Three tabs. Today and Week carry only dated work; the two piles that would clog them
/// live in Triage, one tap away and badged when the backlog is not empty.
struct RootTabView: View {
    @Environment(MobileEnvironment.self) private var env
    @State private var selection = {
        #if DEBUG
        return DebugHooks.requestedTab ?? 0
        #else
        return 0
        #endif
    }()

    @State private var isAdding = false

    /// What a new task defaults to, following whichever tab you're looking at. An explicit
    /// date typed into the sheet still overrides this.
    private var addDefaultDay: Day? {
        switch selection {
        case 1:
            // Adding from a past or future week defaults to that week's first day rather
            // than today, so the task lands where you were looking.
            return env.week.contains(.today()) ? .today() : env.week.first
        case 2:
            // Triage is the pile for things without a day yet.
            return nil
        default:
            return .today()
        }
    }

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
        .overlay(alignment: .bottomTrailing) {
            FloatingAddButton { isAdding = true }
                .padding(.trailing, 20)
                // Clears the floating tab bar rather than sitting on top of it.
                .padding(.bottom, 96)
        }
        .sheet(isPresented: $isAdding) {
            QuickAddSheet(defaultDay: addDefaultDay).environment(env)
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
