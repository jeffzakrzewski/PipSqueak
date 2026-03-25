import SwiftUI

struct NextMeetingCard: View {
    let meeting: MeetingEvent
    let countdownManager: CountdownManager

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
                Text(meeting.startDate, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
                            Text(formatRemaining(remaining))
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
                        link.launch()
                    } label: {
                        Label("Join \(link.provider.rawValue)", systemImage: link.provider.iconName)
                            .font(.subheadline)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func formatRemaining(_ totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
