import EventKit
import Foundation

@MainActor
@Observable
final class CalendarManager {
    let eventStore = EKEventStore()

    var authorizationStatus: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    var allCalendars: [EKCalendar] = []
    var upcomingEvents: [MeetingEvent] = []
    var recentEvents: [MeetingEvent] = []

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

    func fetchUpcomingEvents(
        selectedCalendarIDs: Set<String>,
        showEventsWithoutLinks: Bool = false,
        onlyToday: Bool = false
    ) {
        guard authorizationStatus == .fullAccess else { return }

        let calendars = allCalendars.filter { selectedCalendarIDs.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else {
            upcomingEvents = []
            recentEvents = []
            return
        }

        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
        let end = onlyToday ? endOfDay : Calendar.current.date(byAdding: .day, value: 7, to: now)!

        // Fetch events
        let predicate = eventStore.predicateForEvents(withStart: startOfDay, end: end, calendars: calendars)

        let allEvents = eventStore.events(matching: predicate)
            .filter { !$0.isAllDay }
            .filter { !self.isDeclined($0) }

        let meetingEvents = allEvents.map { MeetingEvent(from: $0) }

        // Upcoming: haven't ended yet (includes currently active)
        upcomingEvents = meetingEvents
            .filter { $0.endDate > now }
            .filter { showEventsWithoutLinks || $0.meetingLink != nil }
            .sorted { $0.startDate < $1.startDate }

        // Recent: already ended today, only those with meeting links (for joining late)
        recentEvents = meetingEvents
            .filter { $0.endDate <= now && $0.startDate >= startOfDay }
            .filter { $0.meetingLink != nil }
            .sorted { $0.startDate > $1.startDate }
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
