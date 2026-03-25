import SwiftUI

struct TimerSettingsView: View {
    @Environment(AppState.self) private var appState

    private let durations: [(label: String, value: Double)] = [
        ("15 seconds", 15),
        ("30 seconds", 30),
        ("60 seconds", 60),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Countdown Settings")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Start audio countdown before meeting:")
                    .font(.subheadline)

                Picker("Lead-in duration", selection: Binding(
                    get: { appState.leadInDuration },
                    set: { appState.leadInDuration = $0 }
                )) {
                    ForEach(durations, id: \.value) { duration in
                        Text(duration.label).tag(duration.value)
                    }
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
