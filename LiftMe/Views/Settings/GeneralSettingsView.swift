import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("General Settings")
                .font(.headline)

            Toggle(isOn: Binding(
                get: { appState.launchAtLogin },
                set: { newValue in
                    appState.launchAtLogin = newValue
                    toggleLaunchAtLogin(newValue)
                }
            )) {
                VStack(alignment: .leading) {
                    Text("Launch at Login")
                    Text("Start LiftMe automatically when you log in")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("About LiftMe")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text("A meeting countdown timer for your menu bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Plays countdown music with the pips landing exactly when your meeting starts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Quit LiftMe") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding()
    }

    private func toggleLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Silently fail -- user can retry
            appState.launchAtLogin = !enabled
        }
    }
}
