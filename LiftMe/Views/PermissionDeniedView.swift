import SwiftUI

struct PermissionDeniedView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 32))
                .foregroundStyle(.orange)

            Text("Calendar Access Required")
                .font(.headline)

            Text("LiftMe needs access to your calendars to show meeting countdowns.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if appState.calendarManager.authorizationStatus == .notDetermined {
                Button("Grant Access") {
                    Task {
                        await appState.calendarManager.requestAccess()
                        if appState.calendarManager.authorizationStatus == .fullAccess {
                            appState.calendarManager.loadCalendars()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)

                Text("Enable LiftMe in System Settings > Privacy & Security > Calendars")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }
}
