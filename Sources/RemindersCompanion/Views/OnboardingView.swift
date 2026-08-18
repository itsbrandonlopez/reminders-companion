import RemindersCore
import SwiftUI

/// First-run setup.
///
/// Two things need to happen before the app is useful: it needs permission to read the
/// user's reminders, and it needs to know which lists they actually plan with. Asking
/// both up front — with the reason stated before the system prompt appears — converts far
/// better than dropping someone onto an empty board behind a bare permission dialog.
///
/// Calendar access is asked for separately and can be skipped outright, because the app
/// is fully functional without it.
struct OnboardingView: View {
    @Environment(AppEnvironment.self) private var env

    enum Step: Int, CaseIterable {
        case welcome, reminders, lists, calendar, ready
    }

    @State private var step: Step = .welcome
    @State private var isWorking = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 26) {
                content
                    .frame(maxWidth: 460)
                    .transition(.opacity)

                controls
            }
            .padding(.horizontal, 48)

            Spacer(minLength: 0)

            stepIndicator
                .padding(.bottom, 26)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.window)
        .animation(.easeInOut(duration: 0.22), value: step)
    }

    // MARK: - Steps

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome: welcome
        case .reminders: remindersAccess
        case .lists: listPicker
        case .calendar: calendarAccess
        case .ready: ready
        }
    }

    private var welcome: some View {
        VStack(spacing: 18) {
            Hero(symbol: "calendar.day.timeline.left", tint: Palette.accent)

            VStack(spacing: 8) {
                Text("Reminders Companion")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                Text("Plan your week with the tasks you already have.")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.textSecondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                Promise(symbol: "arrow.triangle.2.circlepath",
                        title: "Your tasks stay in Reminders",
                        detail: "Nothing is imported or duplicated. This is a different way to look at the reminders you already have.")
                Promise(symbol: "bell.badge",
                        title: "Your notifications never change",
                        detail: "Rescheduling a task here cannot alter when — or whether — a reminder alerts you.")
                Promise(symbol: "lock",
                        title: "Everything stays on this Mac",
                        detail: "No account, no server, no analytics. Your tasks are never sent anywhere.")
            }
            .padding(.top, 4)
        }
    }

    private var remindersAccess: some View {
        VStack(spacing: 18) {
            Hero(symbol: "checklist", tint: Palette.accent)
            Title("Connect your reminders",
                  subtitle: "Reminders Companion needs permission to read and reschedule your reminders. That access is what puts them on the board — there is no other copy of your data.")

            if env.store.access == .denied {
                Callout(
                    symbol: "exclamationmark.triangle.fill",
                    tint: Palette.overdue,
                    text: "Access was declined. The app can't show anything without it."
                )
                Button("Open Privacy Settings") { env.store.openPrivacySettings() }
                    .buttonStyle(.borderedProminent)
            } else if env.store.access == .granted {
                Callout(
                    symbol: "checkmark.circle.fill",
                    tint: Palette.accent,
                    text: "Connected — \(env.store.lists.count) lists, \(env.store.tasks.count) open tasks."
                )
            }
        }
    }

    private var listPicker: some View {
        VStack(spacing: 16) {
            Title("Choose what to plan with",
                  subtitle: "Pick the lists you want on your boards. Everything else stays in Reminders, untouched — you can change this any time from the sidebar.")

            HStack(spacing: 12) {
                Button("Select All") { env.includeAllLists() }
                    .buttonStyle(.link)
                    .tint(Palette.accent)
                Spacer()
                Text("\(env.visibleLists.count) of \(env.store.lists.count) selected")
                    .foregroundStyle(Palette.textTertiary)
            }
            .font(.system(size: 12))

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(env.store.lists) { list in
                        SetupListRow(list: list, count: env.count(for: list), isOn: binding(for: list))
                    }
                }
            }
            .frame(maxHeight: 260)
        }
    }

    private var calendarAccess: some View {
        VStack(spacing: 18) {
            Hero(symbol: "calendar.badge.clock", tint: Palette.flag)
            Title("See what's already booked",
                  subtitle: "Overlay your calendar so you can tell at a glance which days are full before you plan into them. Events are only ever read — never created, changed or deleted.")

            switch env.store.eventAccess {
            case .granted:
                if env.store.calendars.isEmpty {
                    Callout(symbol: "info.circle.fill", tint: Palette.textSecondary,
                            text: "No calendars found on this Mac.")
                } else {
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(env.store.calendars) { calendar in
                                SetupCalendarRow(
                                    calendar: calendar,
                                    isOn: Binding(
                                        get: { env.overlayCalendarIDs.contains(calendar.id) },
                                        set: { on in
                                            if on { env.overlayCalendarIDs.insert(calendar.id) }
                                            else { env.overlayCalendarIDs.remove(calendar.id) }
                                        }
                                    )
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 210)
                }
            case .denied:
                Callout(symbol: "info.circle.fill", tint: Palette.textSecondary,
                        text: "Calendar access is off. Everything else works normally — you can turn it on later from the sidebar.")
            default:
                Text("Optional. You can skip this and enable it later.")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textTertiary)
            }
        }
    }

    private var ready: some View {
        VStack(spacing: 18) {
            Hero(symbol: "sparkles", tint: Palette.accent)
            Title("You're set up",
                  subtitle: summary)

            if env.store.tasks.count < 5 && !env.store.hasSampleData {
                VStack(spacing: 8) {
                    Text("Not much to look at yet?")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Palette.textPrimary)
                    Button("Add a set of demo tasks") {
                        env.pendingSampleAction = .install
                    }
                    .buttonStyle(.bordered)
                    Text("Creates a separate “\(ReminderStore.sampleListName)” list. Your own lists aren't touched.")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 4)
            }
        }
    }

    private var summary: String {
        let lists = env.visibleLists.count
        let tasks = env.filteredTasks.count
        var line = "\(tasks) task\(tasks == 1 ? "" : "s") across \(lists) list\(lists == 1 ? "" : "s")."
        if env.store.eventAccess == .granted, !env.overlayCalendarIDs.isEmpty {
            line += " \(env.overlayCalendarIDs.count) calendar\(env.overlayCalendarIDs.count == 1 ? "" : "s") overlaid."
        }
        return line
    }

    // MARK: - Navigation

    private var controls: some View {
        HStack(spacing: 12) {
            if step != .welcome {
                Button("Back") { goBack() }
                    .buttonStyle(.link)
                    .tint(Palette.textSecondary)
            }
            Spacer()
            if let skip = skipLabel {
                Button(skip) { advance() }
                    .buttonStyle(.link)
                    .tint(Palette.textSecondary)
            }
            Button(primaryLabel) { primaryAction() }
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
                .disabled(isWorking || primaryDisabled)
                .keyboardShortcut(.defaultAction)
        }
        .font(.system(size: 12.5))
        .frame(maxWidth: 460)
    }

    private var primaryLabel: String {
        switch step {
        case .welcome: "Get Started"
        case .reminders: env.store.access == .granted ? "Continue" : "Allow Access"
        case .lists: "Continue"
        case .calendar: env.store.eventAccess == .granted ? "Continue" : "Allow Calendar Access"
        case .ready: "Start Planning"
        }
    }

    /// Optional steps get an explicit way past them, so nobody feels cornered into
    /// granting a permission the app does not require.
    private var skipLabel: String? {
        switch step {
        case .calendar: env.store.eventAccess == .granted ? nil : "Not now"
        default: nil
        }
    }

    private var primaryDisabled: Bool {
        step == .reminders && env.store.access == .denied
    }

    private func primaryAction() {
        switch step {
        case .reminders where env.store.access != .granted:
            Task {
                isWorking = true
                await env.store.requestAccess()
                isWorking = false
                if env.store.access == .granted { advance() }
            }
        case .calendar where env.store.eventAccess != .granted:
            Task {
                isWorking = true
                await env.enableOverlay()
                isWorking = false
                // Stay put when granted so the calendar list can be reviewed.
                if env.store.eventAccess != .granted { advance() }
            }
        case .ready:
            env.completeSetup()
        default:
            advance()
        }
    }

    private func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else {
            env.completeSetup()
            return
        }
        step = next
    }

    private func goBack() {
        if let previous = Step(rawValue: step.rawValue - 1) { step = previous }
    }

    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.rawValue) { s in
                Circle()
                    .fill(s.rawValue <= step.rawValue ? Palette.accent : Palette.cardBorder)
                    .frame(width: 6, height: 6)
            }
        }
    }

    private func binding(for list: TaskList) -> Binding<Bool> {
        Binding(
            get: { env.selectedListIDs.isEmpty || env.selectedListIDs.contains(list.id) },
            set: { isOn in
                if env.selectedListIDs.isEmpty {
                    env.selectedListIDs = Set(env.store.lists.map(\.id))
                }
                if isOn { env.selectedListIDs.insert(list.id) }
                else { env.selectedListIDs.remove(list.id) }
                if env.selectedListIDs.count == env.store.lists.count {
                    env.selectedListIDs.removeAll()
                }
            }
        )
    }
}

// MARK: - Pieces

private struct Hero: View {
    let symbol: String
    let tint: Color

    var body: some View {
        ZStack {
            Circle().fill(tint.opacity(0.14)).frame(width: 68, height: 68)
            Image(systemName: symbol)
                .font(.system(size: 27, weight: .light))
                .foregroundStyle(tint)
        }
    }
}

private struct Title: View {
    let title: String
    let subtitle: String

    init(_ title: String, subtitle: String) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2.5)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct Promise: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(Palette.accent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct Callout: View {
    let symbol: String
    let tint: Color
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 12))
            Text(text).font(.system(size: 12.5))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint.opacity(0.11)))
    }
}

private struct SetupListRow: View {
    let list: TaskList
    let count: Int
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 9) {
                ZStack {
                    Circle().fill(Color(list.color)).frame(width: 18, height: 18)
                    Image(systemName: "list.bullet")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                }
                Text(list.title)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                Text("\(count)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.textTertiary)
                    .monospacedDigit()
            }
        }
        .toggleStyle(.checkbox)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Palette.card))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Palette.cardBorder, lineWidth: 1)
        )
    }
}

private struct SetupCalendarRow: View {
    let calendar: EventCalendar
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color(calendar.color))
                    .frame(width: 12, height: 12)
                Text(calendar.title)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
            }
        }
        .toggleStyle(.checkbox)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Palette.card))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Palette.cardBorder, lineWidth: 1)
        )
    }
}
