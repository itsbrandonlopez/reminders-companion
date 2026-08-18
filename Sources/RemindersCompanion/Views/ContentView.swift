import RemindersCore
import SwiftUI

enum BoardMode: String, CaseIterable, Identifiable {
    case week = "Week"
    case today = "Today"
    var id: String { rawValue }
    var symbol: String { self == .week ? "calendar" : "square.grid.3x1.below.line.grid.1x2" }
}

struct ContentView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var mode: BoardMode = .week

    var body: some View {
        Group {
            if !env.hasCompletedSetup {
                OnboardingView()
            } else {
                switch env.store.access {
                case .granted: board
                case .unknown: ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                // Setup is done but access was revoked afterwards — the gate explains how
                // to restore it without dragging the user back through onboarding.
                default: AccessGateView()
                }
            }
        }
        .background(Palette.window)
        .confirmationDialog(
            sampleTitle,
            isPresented: Binding(
                get: { env.pendingSampleAction != nil },
                set: { if !$0 { env.pendingSampleAction = nil } }
            ),
            presenting: env.pendingSampleAction
        ) { action in
            Button(action == .install ? "Add Demo Tasks" : "Remove Demo List",
                   role: action == .install ? nil : .destructive) {
                env.pendingSampleAction = nil
                Task {
                    if action == .install { await env.store.installSampleData() }
                    else { await env.store.removeSampleData() }
                }
            }
            Button("Cancel", role: .cancel) { env.pendingSampleAction = nil }
        } message: { action in
            Text(action == .install
                 ? "Creates a separate list called “\(ReminderStore.sampleListName)” with a dozen example tasks covering every part of the board. Your existing lists and reminders are not touched, and you can remove it again from the Help menu."
                 : "Deletes the “\(ReminderStore.sampleListName)” list and everything in it. No other list is affected.")
        }
        .task {
            // During setup the permission prompt is triggered by the user, after the
            // reason has been explained. Firing it here would pre-empt that.
            if env.store.access == .notDetermined {
                if env.hasCompletedSetup { await env.store.requestAccess() }
            } else if env.store.access == .granted {
                await env.store.refresh()
            }
            // Restores a previously configured overlay. Never prompts — Calendar access
            // is only ever requested from the sidebar's explicit opt-in.
            env.loadOverlayIfAuthorized()
            // Reminders folders cannot be read by any API, so the two the user already
            // keeps there are created once as a starting point.
            env.seedFoldersIfNeeded()
        }
    }

    private var sampleTitle: String {
        env.pendingSampleAction == .remove ? "Remove the demo list?" : "Add demo tasks?"
    }

    private var board: some View {
        @Bindable var env = env
        return NavigationSplitView {
            SidebarView { focus in
                env.focus = focus
                // Only Today has a board of its own; every other tile lands on the week,
                // where the backlog already has a column. The tiles differ in what they
                // give room to: Backlog and Scheduled fold the unscheduled pool away,
                // All opens it back up.
                mode = (focus == .today) ? .today : .week
                switch focus {
                case .backlog, .scheduled: env.isUnscheduledCollapsed = true
                case .all: env.isUnscheduledCollapsed = false
                case .today, .list: break
                }
            }
            .navigationSplitViewColumnWidth(min: 208, ideal: 232, max: 300)
        } detail: {
            VStack(spacing: 0) {
                if let warning = env.sidecarWarning { banner(warning, color: Palette.flag) }
                if let error = env.store.lastError {
                    banner(error, color: Palette.overdue) { env.store.clearError() }
                }
                if let action = env.store.undoable {
                    undoBanner(for: action)
                }
                switch mode {
                case .week: WeekBoardView()
                case .today: TodayBoardView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: $mode) {
                        ForEach(BoardMode.allCases) { m in
                            Label(m.rawValue, systemImage: m.symbol).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelStyle(.titleOnly)
                    .frame(width: 160)
                    .onChange(of: mode) { _, newValue in
                        // Keep the sidebar honest when the view is switched from the
                        // toolbar rather than from a tile.
                        if newValue == .today, env.focus != .today { env.focus = .today }
                        if newValue == .week, env.focus == .today { env.focus = .scheduled }
                    }
                }
                ToolbarItem(placement: .automatic) { ListFilterMenu() }
            }
            .searchable(text: $env.searchText, placement: .toolbar, prompt: "Search tasks")
        }
        .tint(Palette.accent)
    }

    /// Every edit here writes straight through to Reminders, and a completed task drops
    /// out of the board immediately, so without this a mis-drop or mis-click is only
    /// recoverable by opening Reminders.app.
    private func undoBanner(for action: UndoableAction) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.uturn.backward.circle.fill").font(.system(size: 11))
            Text("\(action.label) “\(action.task.title)”")
                .font(.system(size: 11.5)).lineLimit(1)
            Spacer()
            Button("Undo") { Task { await env.store.undoLast() } }
                .buttonStyle(.borderless)
                .font(.system(size: 11.5, weight: .medium))
            Button {
                env.store.dismissUndo()
            } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.borderless)
        }
        .foregroundStyle(Palette.accent)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Palette.accent.opacity(0.11))
    }

    private func banner(_ text: String, color: Color, dismiss: (() -> Void)? = nil) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill").font(.system(size: 11))
            Text(text).font(.system(size: 11.5))
            Spacer()
            if let dismiss {
                Button("Dismiss", action: dismiss)
                    .buttonStyle(.borderless)
                    .font(.system(size: 11.5))
            }
        }
        .foregroundStyle(color)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(color.opacity(0.11))
    }
}
