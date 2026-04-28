import SwiftUI

struct NextMeetingCard: View {
    let meeting: MeetingEvent
    let countdownManager: CountdownManager
    var browserProfileManager: BrowserProfileManager?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let color = meeting.calendarColor {
                    Circle()
                        .fill(Color(cgColor: color) ?? .blue)
                        .frame(width: 8, height: 8)
                }
                Text(meeting.calendarTitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 2) {
                    Text(meeting.startDate, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if !meeting.dayIndicator.isEmpty {
                        Text(meeting.dayIndicator)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Text(meeting.title)
                .font(.headline)
                .lineLimit(2)

            HStack {
                switch countdownManager.meetingState {
                case .upcoming:
                    let remaining = countdownManager.remainingSeconds
                    if remaining <= 60 {
                        Label {
                            Text("\(remaining)s")
                                .monospacedDigit()
                                .foregroundStyle(.orange)
                                .fontWeight(.bold)
                        } icon: {
                            Image(systemName: "speaker.wave.3.fill")
                                .foregroundStyle(.orange)
                                .symbolEffect(.variableColor.iterative, isActive: remaining <= 30)
                        }
                        .font(.title2)
                    } else {
                        Label {
                            Text(MeetingTimeFormatter.format(remaining, style: .colon))
                                .monospacedDigit()
                        } icon: {
                            Image(systemName: "clock")
                        }
                        .font(.title3)
                        .foregroundStyle(.primary)
                    }
                case .inMeeting:
                    Label("In progress", systemImage: "person.wave.2.fill")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                default:
                    EmptyView()
                }

                Spacer()

                if let link = meeting.meetingLink {
                    Button {
                        link.launch(calendarAccountEmail: meeting.calendarAccountEmail, browserProfileManager: browserProfileManager)
                    } label: {
                        Label("Join \(link.provider.rawValue)", systemImage: link.provider.iconName)
                            .font(.subheadline)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityLabel("Join \(meeting.title)")
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
