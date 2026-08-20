import RemindersCore
import SwiftUI

/// What the sidebar is pointing at, and the only thing that decides which view the
/// window shows.
///
/// Three cases, because there are three kinds of view: the week board, the today board,
/// and one list on its own. The tiles used to carry five — Scheduled, All and Backlog all
/// opened the same week board with a flag flipped, which made them three names for one
/// thing rather than three views.
enum SidebarFocus: Hashable {
    case week
    case today
    case list(String)
}

/// A close copy of the Reminders sidebar — smart tiles above a "My Lists" section of
/// colour-dotted rows, organised into collapsible folders.
///
/// Two tiles rather than Reminders' four, and they are this app's two boards rather than
/// saved searches. Reminders' Flagged and Completed have nothing to point at here — flags
/// are absent from EventKit entirely, and completed items need a fetch this app does not
/// do. Backlog is not a tile either: it is already a column on the Week board, so a tile
/// for it would have opened the very view it lives in. It survives as the count badged on
/// the Week tile, which is the part that was actually worth glancing at.
struct SidebarView: View {
    @Environment(AppEnvironment.self) private var env
    let onSelect: (SidebarFocus) -> Void

    @State private var isCreatingFolder = false
    @State private var newFolderName = ""
    @State private var renaming: ListFolder?
    @State private var renameText = ""

    private let columns = [
        GridItem(.flexible(), spacing: 9),
        GridItem(.flexible(), spacing: 9),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: columns, spacing: 9) {
                    SmartTile(
                        title: "Today", symbol: "sun.max.fill", tint: Palette.accent,
                        count: env.todayCount, isSelected: env.focus == .today
                    ) { onSelect(.today) }

                    SmartTile(
                        title: "Week", symbol: "calendar", tint: Palette.flag,
                        count: env.scheduledCount, isSelected: env.focus == .week,
                        // The one number the retired Backlog tile was carrying. It rides
                        // here because the backlog is a column on the board this opens.
                        badge: env.backlog.count,
                        badgeTint: Palette.overdue,
                        badgeHelp: "\(env.backlog.count) in backlog"
                    ) { onSelect(.week) }
                }

                listsSection
                CalendarOverlaySection()
                SidecarStatusRow()
            }
            .padding(12)
        }
        .scrollContentBackground(.hidden)
        .background(Palette.sidebar)
        .alert("New Folder", isPresented: $isCreatingFolder) {
            TextField("Name", text: $newFolderName)
            Button("Cancel", role: .cancel) { newFolderName = "" }
            Button("Create") {
                env.createFolder(named: newFolderName)
                newFolderName = ""
            }
        } message: {
            Text("Folders live in this app only — Reminders does not expose its own.")
        }
        .alert("Rename Folder", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Rename") {
                if let folder = renaming { env.rename(folder, to: renameText) }
                renaming = nil
            }
        }
    }

    private var listsSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text("My Lists")
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                Button {
                    newFolderName = ""
                    isCreatingFolder = true
                } label: {
                    Image(systemName: "folder.badge.plus").font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.textSecondary)
                .help("New folder")

                ListFilterMenu()
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 4)

            ForEach(env.folders) { folder in
                FolderSection(
                    folder: folder,
                    onSelect: onSelect,
                    onRename: {
                        renameText = folder.name
                        renaming = folder
                    }
                )
            }

            // Un-foldered lists sit below the folders, as they do in Reminders.
            ForEach(env.ungroupedLists) { list in
                ListRow(list: list, isSelected: env.focus == .list(list.id)) {
                    onSelect(.list(list.id))
                }
            }
        }
    }
}

private struct FolderSection: View {
    let folder: ListFolder
    let onSelect: (SidebarFocus) -> Void
    let onRename: () -> Void

    @Environment(AppEnvironment.self) private var env
    @State private var isHovering = false
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button { env.toggleCollapsed(folder) } label: {
                HStack(spacing: 7) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Palette.textSecondary)
                        .rotationEffect(.degrees(folder.isCollapsed ? 0 : 90))
                    Image(systemName: "folder.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.accent)
                    Text(folder.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("\(env.count(in: folder))")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.textTertiary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isTargeted ? Palette.accent.opacity(0.18)
                              : (isHovering ? Palette.card.opacity(0.7) : .clear))
                )
                // A shape filled with `.clear` is not hit-testable, so an unselected row's
                // background was dead to the mouse and only its text and icon could be
                // clicked. This makes the whole row the target, which is what it looks like.
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .contextMenu {
                Button("Rename…", action: onRename)
                Button("Delete Folder", role: .destructive) { env.delete(folder) }
            }
            // Dragging a list row onto the folder files it, which is quicker than the menu.
            .dropDestination(for: String.self) { ids, _ in
                guard let id = ids.first else { return false }
                env.assign(listID: id, to: folder)
                return true
            } isTargeted: { isTargeted = $0 }

            if !folder.isCollapsed {
                ForEach(env.lists(in: folder)) { list in
                    ListRow(list: list, isSelected: env.focus == .list(list.id), indented: true) {
                        onSelect(.list(list.id))
                    }
                }
                if env.lists(in: folder).isEmpty {
                    Text("Drag lists here")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.leading, 30)
                        .padding(.vertical, 3)
                }
            }
        }
    }
}

private struct SmartTile: View {
    let title: String
    let symbol: String
    let tint: Color
    let count: Int
    let isSelected: Bool
    /// A secondary count that wants attention, shown beside the title. Hidden at zero.
    var badge: Int = 0
    var badgeTint: Color = Palette.overdue
    var badgeHelp: String = ""
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    ZStack {
                        Circle().fill(tint).frame(width: 24, height: 24)
                        Image(systemName: symbol)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    Text("\(count)")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .monospacedDigit()
                }
                HStack(spacing: 5) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if badge > 0 {
                        HStack(spacing: 2.5) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 8.5, weight: .semibold))
                            Text("\(badge)")
                                .font(.system(size: 10, weight: .semibold))
                                .monospacedDigit()
                        }
                        .foregroundStyle(badgeTint)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(
                            Capsule().fill(badgeTint.opacity(0.16))
                        )
                        .help(badgeHelp)
                    }
                }
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? tint.opacity(0.18) : Palette.card.opacity(isHovering ? 1 : 0.75))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(isSelected ? tint.opacity(0.55) : Palette.cardBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct ListRow: View {
    let list: TaskList
    let isSelected: Bool
    var indented = false
    let action: () -> Void

    @Environment(AppEnvironment.self) private var env
    @State private var isHovering = false

    private var isIncluded: Bool {
        env.selectedListIDs.isEmpty || env.selectedListIDs.contains(list.id)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                ZStack {
                    Circle().fill(Color(list.color)).frame(width: 21, height: 21)
                    Image(systemName: "list.bullet")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
                Text(list.title)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if !isIncluded {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 9))
                        .foregroundStyle(Palette.textTertiary)
                        .help("Hidden from the Week and Today boards")
                }
                Text("\(env.count(for: list))")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textTertiary)
                    .monospacedDigit()
            }
            .padding(.leading, indented ? 23 : 7)
            .padding(.trailing, 7)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Palette.accent.opacity(0.16)
                          : (isHovering ? Palette.card.opacity(0.7) : .clear))
            )
            // Same reason as the folder header: without this the clickable area is the
            // text and the dot, not the row.
            .contentShape(Rectangle())
            .opacity(isIncluded ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .draggable(list.id)
        .contextMenu {
            Menu("Move to Folder") {
                Button("None") { env.assign(listID: list.id, to: nil) }
                Divider()
                ForEach(env.folders) { folder in
                    Button(folder.name) { env.assign(listID: list.id, to: folder) }
                }
            }
        }
    }
}

/// The checkmarks that decide which lists take part in the Week and Today boards.
struct ListFilterMenu: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Menu {
            Button("Show All Lists") { env.selectedListIDs.removeAll() }
            Divider()
            ForEach(env.store.lists) { list in
                Toggle(list.title, isOn: binding(for: list))
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 12.5))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(Palette.textSecondary)
        .help("Choose which lists appear on the boards")
    }

    private func binding(for list: TaskList) -> Binding<Bool> {
        Binding(
            get: { env.selectedListIDs.isEmpty || env.selectedListIDs.contains(list.id) },
            set: { isOn in
                // Empty means "all lists". The first explicit untick has to seed the set
                // from every list, or it would hide the other ten instead of just this one.
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

/// Says whether the sidecar — manual order, estimates, folders, sections — is reaching
/// your other devices.
///
/// Worth a permanent line rather than a one-off alert: everything it covers is invisible
/// to Reminders, so "I named these sections on the Mac and my phone doesn't have them" is
/// a question this answers before it gets asked.
private struct SidecarStatusRow: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 10))
            Text(label).font(.system(size: 11))
            Spacer(minLength: 0)
        }
        .foregroundStyle(Palette.textTertiary)
        .padding(.horizontal, 7)
        .help(explanation)
    }

    private var symbol: String {
        switch env.sidecarStorage {
        case .cloud: "icloud.fill"
        case .local: "internaldrive"
        case .memory: "exclamationmark.triangle"
        }
    }

    private var label: String {
        switch env.sidecarStorage {
        case .cloud: "Order and sections sync"
        case .local: "Order and sections: this Mac"
        case .memory: "Not being saved"
        }
    }

    private var explanation: String {
        switch env.sidecarStorage {
        case .cloud:
            "Manual order, estimates, folders and sections are syncing through iCloud. Your tasks themselves have always synced through Reminders."
        case .local:
            "Manual order, estimates, folders and sections are stored on this Mac only. Syncing them needs a build signed with an Apple Developer identity — see make.sh. Your tasks are unaffected: they sync through Reminders as always."
        case .memory:
            "The sidecar could not be opened, so ordering, estimates, folders and sections will be lost when the app quits. Your tasks are safe in Reminders."
        }
    }
}

/// Chooses which calendars are drawn over the week.
///
/// Calendar access is a separate permission from Reminders and is asked for only when
/// this is switched on, so someone who never wants the overlay is never prompted.
struct CalendarOverlaySection: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    env.isCalendarsCollapsed.toggle()
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Palette.textSecondary)
                        .rotationEffect(.degrees(env.isCalendarsCollapsed ? 0 : 90))
                    Text("Calendars")
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundStyle(Palette.textPrimary)
                    Spacer()
                    if env.isCalendarsCollapsed, !env.overlayCalendarIDs.isEmpty {
                        Text("\(env.overlayCalendarIDs.count)")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !env.isCalendarsCollapsed { content }
        }
    }

    @ViewBuilder private var content: some View {
        switch env.store.eventAccess {
        case .granted:
            if env.store.calendars.isEmpty {
                Text("No calendars found")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.horizontal, 7)
            } else {
                ForEach(env.store.calendars) { calendar in
                    CalendarToggleRow(calendar: calendar, isOn: binding(for: calendar))
                }
            }

        case .denied:
            VStack(alignment: .leading, spacing: 5) {
                Text("Calendar access is off, so gigs can't be shown.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Privacy Settings") { env.store.openPrivacySettings() }
                    .buttonStyle(.link)
                    .font(.system(size: 11.5))
            }
            .padding(.horizontal, 7)

        default:
            Button {
                Task { await env.enableOverlay() }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "calendar.badge.plus").font(.system(size: 11))
                    Text("Show Calendar Events").font(.system(size: 12))
                }
                .foregroundStyle(Palette.accent)
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
            }
            .buttonStyle(.plain)
        }
    }

    private func binding(for calendar: EventCalendar) -> Binding<Bool> {
        Binding(
            get: { env.overlayCalendarIDs.contains(calendar.id) },
            set: { isOn in
                if isOn { env.overlayCalendarIDs.insert(calendar.id) }
                else { env.overlayCalendarIDs.remove(calendar.id) }
            }
        )
    }
}

private struct CalendarToggleRow: View {
    let calendar: EventCalendar
    @Binding var isOn: Bool
    @State private var isHovering = false

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color(calendar.color))
                    .frame(width: 11, height: 11)
                Text(calendar.title)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .toggleStyle(.checkbox)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isHovering ? Palette.card.opacity(0.7) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}
