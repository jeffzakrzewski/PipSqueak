import SwiftUI

struct PopoverView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            if appState.calendarManager.authorizationStatus != .fullAccess {
                PermissionDeniedView()
                    .environment(appState)
            } else if appState.selectedCalendarIDs.isEmpty {
                onboardingView
            } else {
                meetingContent
            }

            Divider()
                .padding(.vertical, 4)

            bottomBar
        }
        .frame(width: 320)
        .padding(.vertical, 8)
        .task {
            await appState.start()
        }
    }

    private var onboardingView: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)

            Text("Select Calendars")
                .font(.headline)

            Text("Choose which calendars to monitor for meetings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Select All Calendars") {
                appState.selectAllCalendars()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

            Button("Open Settings...") {
                openSettings()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding()
    }

    private var meetingContent: some View {
        VStack(spacing: 8) {
            if let meeting = appState.countdownManager.currentMeeting {
                NextMeetingCard(meeting: meeting, countdownManager: appState.countdownManager)
            } else {
                noMeetingsView
            }

            if appState.calendarManager.upcomingEvents.count > 1 {
                UpcomingMeetingsList(
                    events: Array(appState.calendarManager.upcomingEvents.prefix(5)),
                    currentMeetingID: appState.countdownManager.currentMeeting?.id
                )
            }
        }
        .padding(.horizontal, 12)
    }

    private var noMeetingsView: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 24))
                .foregroundStyle(.green)
            Text("No upcoming meetings")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
    }

    private var bottomBar: some View {
        HStack {
            Button {
                appState.audioManager.updateVolume(appState.audioManager.volume > 0 ? 0 : Float(appState.audioVolume))
            } label: {
                Image(systemName: appState.audioManager.volume > 0 ? "speaker.wave.2.fill" : "speaker.slash.fill")
            }
            .buttonStyle(.borderless)
            .help(appState.audioManager.volume > 0 ? "Mute" : "Unmute")

            Spacer()

            Button("Settings...") {
                openSettings()
            }
            .buttonStyle(.borderless)

            Divider()
                .frame(height: 16)

            Button("Quit LiftMe") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private func openSettings() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if #available(macOS 14, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }

        // Restore accessory policy when settings close
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let settingsWindow = NSApp.windows.first(where: {
                $0.identifier?.rawValue.contains("Settings") ?? false ||
                $0.identifier?.rawValue.contains("Preferences") ?? false
            }) {
                NotificationCenter.default.addObserver(
                    forName: NSWindow.willCloseNotification,
                    object: settingsWindow,
                    queue: .main
                ) { _ in
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }
}
