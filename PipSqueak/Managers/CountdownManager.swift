import AppKit
import Foundation

@MainActor
@Observable
final class CountdownManager {
    var currentMeeting: MeetingEvent?
    var remainingSeconds: Int = 0
    var isCountingDown: Bool = false
    var meetingState: MeetingState = .idle
    var compact: Bool = false

    /// Called once per timer tick. AppState uses this to drive audio scheduling
    /// without coupling CountdownManager to AppState.
    var onTick: (() -> Void)?

    private var timer: Timer?

    enum MeetingState: Equatable {
        case idle
        case upcoming(MeetingEvent)
        case inMeeting(MeetingEvent)

        static func == (lhs: MeetingState, rhs: MeetingState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle): return true
            case (.upcoming(let a), .upcoming(let b)): return a.id == b.id
            case (.inMeeting(let a), .inMeeting(let b)): return a.id == b.id
            default: return false
            }
        }
    }

    var menuBarTitle: String {
        switch meetingState {
        case .idle:
            return ""
        case .upcoming(let meeting):
            // Don't show countdown for meetings past tomorrow
            if meeting.daysFromToday > 1 {
                return compact ? "" : meeting.truncatedTitle
            }
            if remainingSeconds <= 0 {
                return compact ? "Now" : "In: \(meeting.truncatedTitle)"
            }
            let time = MeetingTimeFormatter.format(remainingSeconds, style: .compact)
            return compact ? "in \(time)" : "\(meeting.truncatedTitle) in \(time)"
        case .inMeeting(let meeting):
            return compact ? "In mtg" : "In: \(meeting.truncatedTitle)"
        }
    }

    var leadInDuration: Int = 30

    var menuBarIcon: String {
        switch meetingState {
        case .idle:
            return "calendar"
        case .upcoming:
            if remainingSeconds <= leadInDuration {
                return "speaker.wave.3.fill"
            }
            return "calendar.badge.clock"
        case .inMeeting:
            return "person.wave.2.fill"
        }
    }

    func startObserving() {
        // Wake handling is centralized in AppState. CountdownManager does not
        // observe system events directly anymore — kept for symmetry with
        // stopObserving() which still tears down the timer.
    }

    func stopObserving() {
        timer?.invalidate()
        timer = nil
    }

    func update(with events: [MeetingEvent]) {
        let now = Date()

        // Find current active meeting
        if let activeMeeting = events.first(where: { now >= $0.startDate && now < $0.endDate }) {
            let nextAfterCurrent = events.first(where: { $0.startDate > now })
            // Intentional: when an upcoming meeting is within 5 minutes while
            // the current meeting is still active, hand off currentMeeting to
            // the upcoming one. The menu bar reflects the next meeting and
            // audio scheduling for that upcoming meeting is acceptable per
            // design — even though the current meeting is still in progress.
            if let next = nextAfterCurrent, next.timeUntilStart <= 300 {
                setUpcoming(next)
            } else {
                meetingState = .inMeeting(activeMeeting)
                currentMeeting = activeMeeting
            }
        } else if let nextMeeting = events.first(where: { $0.startDate > now }) {
            setUpcoming(nextMeeting)
        } else {
            meetingState = .idle
            currentMeeting = nil
            stopTimer()
        }
    }

    private func setUpcoming(_ meeting: MeetingEvent) {
        meetingState = .upcoming(meeting)
        currentMeeting = meeting
        if !isCountingDown {
            startTimer()
        }
    }

    func startTimer() {
        stopTimer()
        isCountingDown = true
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
        tick()
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
        isCountingDown = false
    }

    private func tick() {
        guard let meeting = currentMeeting else { return }
        let now = Date()

        if now >= meeting.endDate {
            meetingState = .idle
            currentMeeting = nil
            stopTimer()
            onTick?()
            return
        }

        if now >= meeting.startDate {
            meetingState = .inMeeting(meeting)
            remainingSeconds = 0
        } else {
            remainingSeconds = max(0, Int(ceil(meeting.startDate.timeIntervalSince(now))))
            meetingState = .upcoming(meeting)
        }
        onTick?()
    }
}
