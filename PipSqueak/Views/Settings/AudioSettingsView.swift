import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AudioSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        VStack(alignment: .leading, spacing: 16) {
            // Countdown Sound
            VStack(alignment: .leading, spacing: 8) {
                Text("Countdown Sound")
                    .font(.headline)

                HStack {
                    audioStatusLabel

                    Spacer()

                    if appState.audioManager.isAudioLoaded {
                        Text(formatDuration(appState.audioManager.audioDuration))
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Button(appState.audioManager.isPlaying ? "Stop" : "Preview") {
                        if appState.audioManager.isPlaying {
                            appState.audioManager.cancelPlayback()
                        } else {
                            appState.audioManager.previewAudio()
                        }
                    }
                    .disabled(!appState.audioManager.isAudioLoaded)

                    Button("Choose File...") {
                        chooseCustomAudio()
                    }

                    if !appState.customAudioBookmarkData.isEmpty {
                        Button("Reset to Default") {
                            appState.customAudioBookmarkData = Data()
                            appState.audioManager.loadBundledAudio()
                        }
                    }
                }

                if !appState.audioManager.isAudioLoaded {
                    Text("No audio file loaded")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Divider()

            // Lead-in timing
            VStack(alignment: .leading, spacing: 8) {
                Text("Lead-in Timing")
                    .font(.headline)

                Text("How long before the meeting should the countdown start?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker("Lead-in duration", selection: $appState.leadInDuration) {
                    Text("15 seconds").tag(15.0)
                    Text("30 seconds").tag(30.0)
                }
                .pickerStyle(.radioGroup)

                Text("The audio is scheduled so the pips land exactly at meeting start time. If the lead-in is shorter than the audio file, playback starts partway through.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Volume
            VStack(alignment: .leading, spacing: 4) {
                Text("Volume")
                    .font(.headline)
                HStack {
                    Image(systemName: "speaker.fill")
                        .foregroundStyle(.secondary)
                    Slider(value: $appState.audioVolume, in: 0...1)
                    Image(systemName: "speaker.wave.3.fill")
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding()
    }

    @ViewBuilder
    private var audioStatusLabel: some View {
        switch appState.audioManager.audioStatus {
        case .ok:
            if appState.customAudioBookmarkData.isEmpty {
                Label("Using default sound", systemImage: "music.note")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Label("Custom sound loaded", systemImage: "music.note")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            }
        case .fallbackToBundled(let reason):
            Label(reason, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(.orange)
        case .failed(let reason):
            Label(reason, systemImage: "xmark.octagon.fill")
                .font(.subheadline)
                .foregroundStyle(.red)
        }
    }

    private func chooseCustomAudio() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mp3, .mpeg4Audio, .wav, .aiff]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select a countdown audio file"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        if let bookmark = appState.audioManager.loadCustomAudio(from: url) {
            appState.customAudioBookmarkData = bookmark
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
