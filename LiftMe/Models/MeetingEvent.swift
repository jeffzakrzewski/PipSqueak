import EventKit
import Foundation

struct MeetingEvent: Identifiable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let calendarTitle: String
    let calendarColor: CGColor?
    let isCurrentlyActive: Bool

    init(from ekEvent: EKEvent) {
        self.id = ekEvent.eventIdentifier
        self.title = ekEvent.title ?? "Untitled"
        self.startDate = ekEvent.startDate
        self.endDate = ekEvent.endDate
        self.calendarTitle = ekEvent.calendar.title
        self.calendarColor = ekEvent.calendar.cgColor
        self.isCurrentlyActive = Date() >= ekEvent.startDate && Date() < ekEvent.endDate
    }

    var truncatedTitle: String {
        if title.count > 25 {
            return String(title.prefix(22)) + "..."
        }
        return title
    }

    var timeUntilStart: TimeInterval {
        startDate.timeIntervalSinceNow
    }

    var timeUntilEnd: TimeInterval {
        endDate.timeIntervalSinceNow
    }
}
