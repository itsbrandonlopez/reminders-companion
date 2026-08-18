import RemindersCore
import SwiftUI

/// The app is a lens onto Reminders, so it has nothing to show without access.
/// Denial is a dead end the user can only escape through System Settings, so that case
/// gets its own explicit path rather than a retry button that will never work.
struct AccessGateView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "checklist")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Palette.accent)

            Text("Reminders Companion")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)

            Group {
                switch env.store.access {
                case .denied:
                    Text("Access to Reminders was turned off. Your tasks stay in Reminders — this app only reads and reschedules them.")
                default:
                    Text("This app plans the reminders you already have. Nothing is copied anywhere, and your existing notifications keep working exactly as they do now.")
                }
            }
            .font(.system(size: 12.5))
            .foregroundStyle(Palette.textSecondary)
            .multilineTextAlignment(.center)
            .lineSpacing(2)
            .frame(maxWidth: 380)

            if env.store.access == .denied {
                Button("Open Privacy Settings") { env.store.openPrivacySettings() }
                    .buttonStyle(.borderedProminent)
                Text("Privacy & Security → Reminders")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textTertiary)
            } else {
                Button("Grant Access to Reminders") {
                    Task { await env.store.requestAccess() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .tint(Palette.accent)
        .padding(44)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.window)
    }
}
