import RemindersCore
import SwiftUI

struct ContentView: View {
    @Environment(AppEnvironment.self) private var env

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

    private var isViewingList: Bool {
        if case .list = env.focus { return true }
        return false
    }

    private var sampleTitle: String {
        env.pendingSampleAction == .remove ? "Remove the demo list?" : "Add demo tasks?"
    }

    private var board: some View {
        @Bindable var env = env
        return NavigationSplitView {
            // The sidebar is now the only view selector, as it is in Reminders. The
            // toolbar's Week/Today picker used to be a second one, which meant two
            // controls to keep agreeing with each other about the same state.
            SidebarView { focus in env.focus = focus }
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
                switch env.focus {
                case .week: WeekBoardView()
                case .today: TodayBoardView()
                case let .list(id): ListDetailView(listID: id)
                }
            }
            // Mounted here rather than inside each view: one button, one position, and it
            // survives switching between them.
            .overlay(alignment: .bottomTrailing) {
                FloatingAddButton()
                    .padding(.trailing, 20)
                    .padding(.bottom, 20)
            }
            .toolbar {
                // The filter decides which lists the two boards aggregate. Inside a single
                // list it would be a control with nothing to act on.
                if !isViewingList {
                    ToolbarItem(placement: .automatic) { ListFilterMenu() }
                }
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
            // A bulk move has no single title to name, so the label carries it alone.
            Text(action.subtitle.map { "\(action.label) “\($0)”" } ?? action.label)
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
