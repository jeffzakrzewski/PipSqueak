import EventKit
import Foundation

@MainActor
@Observable
final class CalendarManager {
    private(set) var eventStore = EKEventStore()

    var authorizationStatus: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    var allCalendars: [EKCalendar] = []
    var upcomingEvents: [MeetingEvent] = []
    var recentEvents: [MeetingEvent] = []

    private var changeObserver: (any NSObjectProtocol)?
    var onCalendarChanged: (() -> Void)?

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

    /// Re-check the system authorization status (useful after the user grants
    /// access in System Settings while the app is running). Returns true if the
    /// status changed since the last published value.
    @discardableResult
    func recheckAuthorization() -> Bool {
        let current = EKEventStore.authorizationStatus(for: .event)
        guard current != authorizationStatus else { return false }
        authorizationStatus = current
        if current == .fullAccess {
            // Recreate the event store; the previous instance was created
            // before access was granted and may not see all calendars.
            eventStore = EKEventStore()
            loadCalendars()
        }
        return true
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

        let predicate = eventStore.predicateForEvents(withStart: startOfDay, end: end, calendars: calendars)
        let store = eventStore

        // Fetch and transform off the main thread; publish results back on main.
        // EKEventStore is documented as thread-safe for read operations; we
        // capture it nonisolated to allow the detached fetch.
        nonisolated(unsafe) let storeRef = store
        nonisolated(unsafe) let predicateRef = predicate

        Task.detached { [weak self] in
            let allEvents = storeRef.events(matching: predicateRef)
                .filter { !$0.isAllDay }
                .filter { !Self.isDeclined($0) }

            let meetingEvents = allEvents.map { MeetingEvent(from: $0) }

            let upcoming = meetingEvents
                .filter { $0.endDate > now }
                .filter { showEventsWithoutLinks || $0.meetingLink != nil }
                .sorted { $0.startDate < $1.startDate }

            let recent = meetingEvents
                .filter { $0.endDate <= now && $0.startDate >= startOfDay }
                .filter { $0.meetingLink != nil }
                .sorted { $0.startDate > $1.startDate }

            await MainActor.run {
                self?.upcomingEvents = upcoming
                self?.recentEvents = recent
            }
        }
    }

    func startObservingChanges() {
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.loadCalendars()
                self?.onCalendarChanged?()
            }
        }
    }

    func stopObservingChanges() {
        if let observer = changeObserver {
            NotificationCenter.default.removeObserver(observer)
            changeObserver = nil
        }
    }

    nonisolated private static func isDeclined(_ event: EKEvent) -> Bool {
        guard let attendees = event.attendees else { return false }
        for attendee in attendees where attendee.isCurrentUser {
            return attendee.participantStatus == .declined
        }
        return false
    }
}
