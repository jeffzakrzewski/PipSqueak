import SwiftUI

struct UpcomingMeetingsList: View {
    let events: [MeetingEvent]
    let currentMeetingID: String?
    var browserProfileManager: BrowserProfileManager?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("UPCOMING")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
                .padding(.top, 4)

            ForEach(filteredEvents) { event in
                HStack(spacing: 8) {
                    if let color = event.calendarColor {
                        Circle()
                            .fill(Color(cgColor: color) ?? .blue)
                            .frame(width: 6, height: 6)
                    }

                    Text(event.truncatedTitle)
                        .font(.caption)
                        .lineLimit(1)

                    Spacer()

                    if let link = event.meetingLink {
                        Button {
                            link.launch(calendarAccountEmail: event.calendarAccountEmail, browserProfileManager: browserProfileManager)
                        } label: {
                            Label("Join", systemImage: link.provider.iconName)
                                .font(.caption2)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .accessibilityLabel("Join \(event.title)")
                    }

                    HStack(spacing: 2) {
                        Text(event.startDate, style: .time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !event.dayIndicator.isEmpty {
                            Text(event.dayIndicator)
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .padding(.vertical, 3)
                .padding(.horizontal, 4)
            }
        }
    }

    private var filteredEvents: [MeetingEvent] {
        events.filter { $0.id != currentMeetingID }
    }
}
