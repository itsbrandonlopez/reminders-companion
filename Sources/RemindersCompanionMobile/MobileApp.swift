import RemindersCore
import SwiftUI

@main
struct RemindersCompanionMobileApp: App {
    @State private var env = MobileEnvironment()

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

            // Test hook, mirroring the Mac app's --selftest: skip setup and seed the demo
            // list so the views can be driven on a Simulator, whose Reminders database
            // starts empty. Never reachable without the launch argument.
            if CommandLine.arguments.contains("--seed-demo"), env.store.access == .granted {
                if !env.store.hasSampleData { await env.store.installSampleData() }
                env.completeSetup()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Coming back from Reminders or another device's edit should not need a pull
            // to refresh — this is a companion, it should already be right.
            guard phase == .active, env.store.access == .granted else { return }
            Task { await env.store.refresh() }
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
