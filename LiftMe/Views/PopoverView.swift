import SwiftUI

struct PopoverView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

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
                showSettings()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding()
    }

    private var meetingContent: some View {
        VStack(spacing: 8) {
            if let meeting = appState.countdownManager.currentMeeting {
                NextMeetingCard(
                    meeting: meeting,
                    countdownManager: appState.countdownManager,
                    browserProfileManager: appState.browserProfileManager
                )
            } else {
                noMeetingsView
            }

            if appState.calendarManager.upcomingEvents.count > 1 {
                UpcomingMeetingsList(
                    events: Array(appState.calendarManager.upcomingEvents.prefix(5)),
                    currentMeetingID: appState.countdownManager.currentMeeting?.id,
                    browserProfileManager: appState.browserProfileManager
                )
            }

            if !appState.calendarManager.recentEvents.isEmpty {
                RecentMeetingsList(
                    events: Array(appState.calendarManager.recentEvents.prefix(3)),
                    browserProfileManager: appState.browserProfileManager
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
                showSettings()
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

    private func showSettings() {
        dismiss()
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "settings")
    }
}
