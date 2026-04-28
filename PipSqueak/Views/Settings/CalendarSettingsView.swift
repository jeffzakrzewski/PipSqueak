import SwiftUI

struct CalendarSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select which calendars to monitor for meetings:")
                .font(.subheadline)

            if appState.calendarManager.authorizationStatus != .fullAccess {
                PermissionDeniedView()
                    .environment(appState)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        let grouped = Dictionary(grouping: appState.calendarManager.allCalendars) { $0.source.title }

                        ForEach(grouped.keys.sorted(), id: \.self) { source in
                            Text(source)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)

                            if let calendars = grouped[source] {
                                ForEach(calendars, id: \.calendarIdentifier) { calendar in
                                    calendarRow(calendar)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)

                HStack {
                    Button("Select All") {
                        appState.selectAllCalendars()
                    }
                    Button("Deselect All") {
                        appState.selectedCalendarIDs = []
                        appState.refreshEvents()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
    }

    @ViewBuilder
    private func calendarRow(_ calendar: EKCalendar) -> some View {
        let isSelected = appState.selectedCalendarIDs.contains(calendar.calendarIdentifier)
        Button {
            appState.toggleCalendar(calendar.calendarIdentifier)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color(cgColor: calendar.cgColor) ?? .blue : .secondary)

                Text(calendar.title)
                    .font(.body)
                    .foregroundStyle(.primary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
        .padding(.leading, 8)
    }
}

import EventKit
