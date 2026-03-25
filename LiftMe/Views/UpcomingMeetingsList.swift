import SwiftUI

struct UpcomingMeetingsList: View {
    let events: [MeetingEvent]
    let currentMeetingID: String?

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

                    Text(event.startDate, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
