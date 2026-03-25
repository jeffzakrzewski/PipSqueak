import SwiftUI

struct AudioSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Audio Settings")
                .font(.headline)

            // Volume
            VStack(alignment: .leading, spacing: 4) {
                Text("Volume")
                    .font(.subheadline)
                HStack {
                    Image(systemName: "speaker.fill")
                        .foregroundStyle(.secondary)
                    Slider(
                        value: Binding(
                            get: { appState.audioVolume },
                            set: {
                                appState.audioVolume = $0
                                appState.audioManager.updateVolume(Float($0))
                            }
                        ),
                        in: 0...1
                    )
                    Image(systemName: "speaker.wave.3.fill")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Custom audio
            VStack(alignment: .leading, spacing: 8) {
                Text("Countdown Sound")
                    .font(.subheadline)

                HStack {
                    if appState.customAudioBookmarkData.isEmpty {
                        Text("Using default sound")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Custom sound loaded")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }

                    Spacer()

                    Button("Choose File...") {
                        if let bookmark = appState.audioManager.selectCustomAudio() {
                            appState.customAudioBookmarkData = bookmark
                        }
                    }

                    if !appState.customAudioBookmarkData.isEmpty {
                        Button("Reset to Default") {
                            appState.customAudioBookmarkData = Data()
                            appState.audioManager.loadBundledAudio()
                        }
                    }
                }

                Button("Preview Sound") {
                    appState.audioManager.previewAudio()
                }
                .disabled(!appState.audioManager.isAudioLoaded)
            }

            Spacer()
        }
        .padding()
    }
}
