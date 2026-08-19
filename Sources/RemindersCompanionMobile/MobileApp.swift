import EventKit
import RemindersCore
import RemindersShared
import SwiftUI
import WidgetKit

@main
struct RemindersCompanionMobileApp: App {
    @State private var env = MobileEnvironment()

    init() {
        // Deliberately here rather than in a view's `.task`. iOS delivers a queued
        // `transferUserInfo` by launching this app in the background, where a WindowGroup's
        // content may never appear — so a view-driven setup would leave the session
        // inactive and the handler unset at exactly the moment the Watch's queued
        // completion arrives. That queued path is the whole point of the feature.
        WatchBridge.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(env)
                .tint(Palette.accent)
        }
    }
}

struct RootView: View {
    @Environment(MobileEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if !env.hasCompletedSetup {
                MobileSetupView()
            } else {
                switch env.store.access {
                case .granted: RootTabView()
                case .unknown: ProgressView()
                default: AccessDeniedView()
                }
            }
        }
        .task {
            if env.store.access == .granted { await env.store.refresh() }
            env.loadOverlayIfAuthorized()
            startWatchBridge()

#if DEBUG
            await DebugHooks.runIfRequested(env: env)
#endif
        }
        .onChange(of: scenePhase) { _, phase in
            // Coming back from Reminders or another device's edit should not need a pull
            // to refresh — this is a companion, it should already be right.
            if phase == .active, env.store.access == .granted {
                Task { await env.store.refresh() }
            }
            // Reloading on the way to the background — rather than after every individual
            // edit — catches every in-app change (schedule, complete, create, delete) with
            // one hook instead of threading a reload call through each view that mutates.
            // It also lands at the moment that matters: nobody is looking at a widget
            // while the app is the thing on screen.
            if phase == .background {
                WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.today)
                WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.nextUp)
            }
        }
        .onOpenURL { url in
            env.handleDeepLink(url)
        }
    }
}

extension RootView {
    /// Listens for completions sent from the paired Watch, which cannot write to
    /// EventKit itself.
    ///
    /// Runs `ReminderStore.completeReminder` — the same static function the widget's
    /// `CompleteTaskIntent` calls — so the Watch, the widget and the app all complete a
    /// task through one code path rather than three that can drift.
    func startWatchBridge() {
        // `setCompleteHandler` drains anything that arrived before the scene appeared,
        // which is the normal case for a background launch.
        WatchBridge.shared.setCompleteHandler { taskID in
            Task { @MainActor in
                let store = EKEventStore()
                _ = try? ReminderStore.completeReminder(externalID: taskID, in: store)
                // The queued path can deliver while the app is backgrounded, so refresh
                // rather than assuming anyone is looking at a live view.
                await env.store.refresh()
                WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.today)
                WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.nextUp)
                // The watch face shows the same counts and is a separate extension.
                WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.watchToday)
            }
        }
    }
}

struct AccessDeniedView: View {
    @Environment(MobileEnvironment.self) private var env

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checklist")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Palette.accent)
            Text("Reminders access is off")
                .font(.title3.weight(.semibold))
            Text("This app shows the reminders you already have. Without access there's nothing to show.")
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
            Button("Open Settings") { env.store.openPrivacySettings() }
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
    }
}
