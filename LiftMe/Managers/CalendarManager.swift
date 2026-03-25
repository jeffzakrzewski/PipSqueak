import EventKit
import Foundation

@MainActor
@Observable
final class CalendarManager {
    let eventStore = EKEventStore()

    var authorizationStatus: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    var allCalendars: [EKCalendar] = []
    var upcomingEvents: [MeetingEvent] = []

    private var changeObserver: (any NSObjectProtocol)?

    func requestAccess() async {
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            authorizationStatus = granted ? .fullAccess : .denied
            if granted {
                loadCalendars()
            }
        } catch {
            authorizationStatus = .denied
        }
    }

    func loadCalendars() {
        allCalendars = eventStore.calendars(for: .event)
    }

    func fetchUpcomingEvents(selectedCalendarIDs: Set<String>) {
        guard authorizationStatus == .fullAccess else { return }

        let calendars = allCalendars.filter { selectedCalendarIDs.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else {
            upcomingEvents = []
            return
        }

        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        let predicate = eventStore.predicateForEvents(withStart: now, end: end, calendars: calendars)

        let ekEvents = eventStore.events(matching: predicate)
            .filter { !$0.isAllDay }
            .filter { !self.isDeclined($0) }
            .sorted { $0.startDate < $1.startDate }

        upcomingEvents = ekEvents.map { MeetingEvent(from: $0) }
    }

    func startObservingChanges() {
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.loadCalendars()
            }
        }
    }

    func stopObservingChanges() {
        if let observer = changeObserver {
            NotificationCenter.default.removeObserver(observer)
            changeObserver = nil
        }
    }

    private func isDeclined(_ event: EKEvent) -> Bool {
        guard let attendees = event.attendees else { return false }
        for attendee in attendees where attendee.isCurrentUser {
            return attendee.participantStatus == .declined
        }
        return false
    }
}
