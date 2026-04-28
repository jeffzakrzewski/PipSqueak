import SwiftUI

struct RecentMeetingsList: View {
    let events: [MeetingEvent]
    var browserProfileManager: BrowserProfileManager?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("RECENT")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
                .padding(.top, 4)

            ForEach(events) { event in
                HStack(spacing: 8) {
                    if let color = event.calendarColor {
                        Circle()
                            .fill(Color(cgColor: color) ?? .blue)
                            .frame(width: 6, height: 6)
                            .opacity(0.5)
                    }

                    Text(event.truncatedTitle)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)

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
                    }

                    Text(event.startDate, style: .time)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 3)
                .padding(.horizontal, 4)
            }
        }
    }
}
