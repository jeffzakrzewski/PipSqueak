import SwiftUI

struct TimerSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        VStack(alignment: .leading, spacing: 16) {
            Text("Countdown Settings")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Start audio countdown before meeting:")
                    .font(.subheadline)

                Picker("Lead-in duration", selection: $appState.leadInDuration) {
                    Text("15 seconds").tag(15.0)
                    Text("30 seconds").tag(30.0)
                    Text("60 seconds").tag(60.0)
                }
                .pickerStyle(.radioGroup)

                Text("The countdown music will begin this many seconds before each meeting, with the final pips landing exactly at meeting start time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
    }
}
