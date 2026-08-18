import RemindersCore
import SwiftUI

/// Two steps, not five. The phone is a companion — the Mac app is where someone is
/// introduced to the idea, so this only needs to get access and pick lists.
struct MobileSetupView: View {
    @Environment(MobileEnvironment.self) private var env
    @State private var step = 0
    @State private var isWorking = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            if step == 0 { welcome } else { lists }
            Spacer()
            controls
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
    }

    private var welcome: some View {
        VStack(spacing: 18) {
            Image(systemName: "calendar.day.timeline.left")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(Palette.accent)
            Text("Reminders Companion")
                .font(.title2.weight(.semibold))
            Text("Your week, on the road.")
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)

            VStack(alignment: .leading, spacing: 14) {
                promise("arrow.triangle.2.circlepath", "Your tasks stay in Reminders",
                        "Nothing is imported or duplicated.")
                promise("bell.badge", "Your notifications never change",
                        "Rescheduling here cannot alter when a reminder alerts you.")
                promise("lock", "Everything stays on this iPhone",
                        "No account, no server, no analytics.")
            }
            .padding(.top, 6)

            if env.store.access == .denied {
                Text("Access was declined. The app can't show anything without it.")
                    .font(.footnote)
                    .foregroundStyle(Palette.overdue)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var lists: some View {
        VStack(spacing: 14) {
            Text("Which lists?")
                .font(.title3.weight(.semibold))
            Text("Pick what you want on your boards. Everything else stays in Reminders, untouched.")
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)

            List {
                ForEach(env.store.lists) { list in
                    Button {
                        toggle(list)
                    } label: {
                        HStack(spacing: 10) {
                            Circle().fill(Color(list.color)).frame(width: 10, height: 10)
                            Text(list.title).foregroundStyle(Palette.textPrimary)
                            Spacer()
                            if isOn(list) {
                                Image(systemName: "checkmark").foregroundStyle(Palette.accent)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Button {
                advance()
            } label: {
                Text(primaryLabel).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isWorking)

            if step == 0, env.store.access == .denied {
                Button("Open Settings") { env.store.openPrivacySettings() }
                    .font(.footnote)
            }
        }
    }

    private var primaryLabel: String {
        if step == 0 { return env.store.access == .granted ? "Continue" : "Connect Reminders" }
        return "Start"
    }

    private func advance() {
        if step == 0 {
            guard env.store.access != .granted else { step = 1; return }
            Task {
                isWorking = true
                await env.store.requestAccess()
                isWorking = false
                if env.store.access == .granted { step = 1 }
            }
        } else {
            env.completeSetup()
        }
    }

    private func isOn(_ list: TaskList) -> Bool {
        env.selectedListIDs.isEmpty || env.selectedListIDs.contains(list.id)
    }

    private func toggle(_ list: TaskList) {
        // Empty means "all", so the first explicit untick has to seed the set from every
        // list or it would hide the rest instead of just this one.
        if env.selectedListIDs.isEmpty {
            env.selectedListIDs = Set(env.store.lists.map(\.id))
        }
        if env.selectedListIDs.contains(list.id) {
            env.selectedListIDs.remove(list.id)
        } else {
            env.selectedListIDs.insert(list.id)
        }
        if env.selectedListIDs.count == env.store.lists.count {
            env.selectedListIDs.removeAll()
        }
    }

    private func promise(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(Palette.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .medium))
                Text(detail).font(.system(size: 12.5)).foregroundStyle(Palette.textSecondary)
            }
        }
    }
}
