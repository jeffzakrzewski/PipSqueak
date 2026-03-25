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

    private var timer: Timer?
    private var wakeObserver: (any NSObjectProtocol)?

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
            if remainingSeconds <= 0 {
                return compact ? "Now" : "In: \(meeting.truncatedTitle)"
            }
            let time = formatTime(remainingSeconds)
            return compact ? "in \(time)" : "\(meeting.truncatedTitle) in \(time)"
        case .inMeeting(let meeting):
            return compact ? "In mtg" : "In: \(meeting.truncatedTitle)"
        }
    }

    var menuBarIcon: String {
        switch meetingState {
        case .idle:
            return "calendar"
        case .upcoming:
            if remainingSeconds <= 60 {
                return "speaker.wave.3.fill"
            }
            return "calendar.badge.clock"
        case .inMeeting:
            return "person.wave.2.fill"
        }
    }

    func startObserving() {
        observeWake()
    }

    func stopObserving() {
        timer?.invalidate()
        timer = nil
        if let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            wakeObserver = nil
        }
    }

    func update(with events: [MeetingEvent]) {
        let now = Date()

        // Find current active meeting
        if let activeMeeting = events.first(where: { now >= $0.startDate && now < $0.endDate }) {
            let nextAfterCurrent = events.first(where: { $0.startDate > now })
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
            return
        }

        if now >= meeting.startDate {
            meetingState = .inMeeting(meeting)
            remainingSeconds = 0
        } else {
            remainingSeconds = max(0, Int(ceil(meeting.startDate.timeIntervalSince(now))))
            meetingState = .upcoming(meeting)
        }
    }

    private func formatTime(_ totalSeconds: Int) -> String {
        if totalSeconds <= 0 { return "0s" }

        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            if minutes == 0 {
                return "\(hours)h"
            }
            return "\(hours)h \(minutes)m"
        }

        if minutes > 0 {
            return "\(minutes)m"
        }

        return "\(seconds)s"
    }

    private func observeWake() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }
}
