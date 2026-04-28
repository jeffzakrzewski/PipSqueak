import SwiftUI

struct ProfileMappingSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Browser Profiles")
                .font(.headline)

            // Default browser info
            HStack {
                Text("Default browser:")
                    .font(.subheadline)
                Text(appState.browserProfileManager.defaultBrowser.rawValue)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                Button("Refresh") {
                    appState.browserProfileManager.detectBrowser()
                }
                .controlSize(.small)
            }

            if !appState.browserProfileManager.defaultBrowser.supportsProfiles {
                noProfileSupportView
            } else if appState.browserProfileManager.profiles.isEmpty {
                noProfilesView
            } else {
                profileMappingList
            }

            Spacer()
        }
        .padding()
        .onAppear {
            appState.browserProfileManager.detectBrowser()
        }
    }

    private var noProfileSupportView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Profile targeting not available", systemImage: "info.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if appState.browserProfileManager.defaultBrowser == .safari {
                Text("Safari does not support programmatic profile selection. Google Meet URLs will still use the ?authuser parameter to select the correct account.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Text("Your default browser does not support profile targeting. Google Meet URLs will still use the ?authuser parameter to select the correct account.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var noProfilesView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No browser profiles found.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Create profiles in \(appState.browserProfileManager.defaultBrowser.rawValue) and they will appear here.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var profileMappingList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Map calendar accounts to browser profiles:")
                .font(.subheadline)

            let calendarEmails = uniqueCalendarEmails

            if calendarEmails.isEmpty {
                Text("No calendar accounts detected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(calendarEmails, id: \.self) { email in
                    mappingRow(email: email)
                }
            }

            Text("Unmapped accounts will use the default profile with ?authuser for Google Meet.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
    }

    private func mappingRow(email: String) -> some View {
        HStack {
            Text(email)
                .font(.body)
                .lineLimit(1)

            Spacer()

            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(.secondary)

            let profiles = appState.browserProfileManager.profiles
            let currentMapping = appState.browserProfileManager.profileMappings[email]

            Picker("", selection: Binding(
                get: { currentMapping ?? "" },
                set: { newValue in
                    if newValue.isEmpty {
                        appState.browserProfileManager.profileMappings.removeValue(forKey: email)
                    } else {
                        appState.browserProfileManager.profileMappings[email] = newValue
                    }
                }
            )) {
                Text("Default").tag("")
                ForEach(profiles) { profile in
                    HStack {
                        Text(profile.displayName)
                        if let profileEmail = profile.email {
                            Text("(\(profileEmail))")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(profile.id)
                }
            }
            .frame(width: 180)
        }
    }

    private var uniqueCalendarEmails: [String] {
        let sources = appState.calendarManager.allCalendars
            .compactMap { calendar -> String? in
                guard calendar.source.sourceType == .calDAV ||
                      calendar.source.sourceType == .subscribed else { return nil }
                return calendar.source.title
            }

        return Array(Set(sources)).sorted()
    }
}
