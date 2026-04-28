import AppKit
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
    let meetingLink: MeetingLink?
    let calendarAccountEmail: String?

    init(from ekEvent: EKEvent) {
        self.id = ekEvent.eventIdentifier
        self.title = ekEvent.title ?? "Untitled"
        self.startDate = ekEvent.startDate
        self.endDate = ekEvent.endDate
        self.calendarTitle = ekEvent.calendar.title
        self.calendarColor = ekEvent.calendar.cgColor
        self.isCurrentlyActive = Date() >= ekEvent.startDate && Date() < ekEvent.endDate
        self.meetingLink = MeetingLink.extract(from: ekEvent)

        // Extract account identifier from calendar source
        let source = ekEvent.calendar.source
        if source?.sourceType == .calDAV || source?.sourceType == .subscribed {
            self.calendarAccountEmail = source?.title
        } else {
            self.calendarAccountEmail = nil
        }
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

    /// Days from today (0 = today, 1 = tomorrow, etc.)
    var daysFromToday: Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: startDate)).day ?? 0
    }

    /// e.g. "+1d" or "+3d", empty string for today
    var dayIndicator: String {
        let days = daysFromToday
        return days > 0 ? "+\(days)d" : ""
    }
}

// MARK: - Meeting Link

struct MeetingLink {
    let url: URL
    let provider: Provider

    enum Provider: String {
        case zoom = "Zoom"
        case teams = "Teams"
        case googleMeet = "Google Meet"
        case webex = "Webex"
        case unknown = "Join"

        var iconName: String {
            switch self {
            case .zoom: return "video.fill"
            case .teams: return "person.2.fill"
            case .googleMeet: return "video.fill"
            case .webex: return "video.fill"
            case .unknown: return "link"
            }
        }
    }

    /// Extract a meeting link from an EKEvent by checking URL, location, and notes
    static func extract(from event: EKEvent) -> MeetingLink? {
        // 1. Check the event URL field
        if let url = event.url, let link = parse(url: url) {
            return link
        }

        // 2. Check the location field
        if let location = event.location, let link = findLink(in: location) {
            return link
        }

        // 3. Check the notes/description field
        if let notes = event.notes, let link = findLink(in: notes) {
            return link
        }

        return nil
    }

    /// Launch the meeting - native app for Zoom/Teams, browser for Meet
    @MainActor
    func launch(calendarAccountEmail: String? = nil, browserProfileManager: BrowserProfileManager? = nil) {
        switch provider {
        case .zoom:
            launchNativeOrBrowser(
                nativeScheme: "zoommtg",
                transform: Self.zoomToNativeURL,
                fallback: url
            )
        case .teams:
            launchNativeOrBrowser(
                nativeScheme: "msteams",
                transform: Self.teamsToNativeURL,
                fallback: url
            )
        case .googleMeet:
            let meetURL = Self.appendAuthUser(to: url, email: calendarAccountEmail)
            print("[LiftMe] Meet launch — account: '\(calendarAccountEmail ?? "nil")', manager: \(browserProfileManager != nil), mappings: \(browserProfileManager?.profileMappings ?? [:])")
            // Use browser profile if mapped, otherwise default browser
            if let manager = browserProfileManager,
               let email = calendarAccountEmail,
               manager.profileMappings[email] != nil {
                manager.launchInProfile(url: meetURL, calendarAccountEmail: email)
            } else {
                NSWorkspace.shared.open(meetURL)
            }
        case .webex, .unknown:
            if let manager = browserProfileManager,
               let email = calendarAccountEmail,
               manager.profileMappings[email] != nil {
                manager.launchInProfile(url: url, calendarAccountEmail: email)
            } else {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private static func appendAuthUser(to url: URL, email: String?) -> URL {
        // Only append authuser when the value is an actual email address
        guard let email = email, email.contains("@") else { return url }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false) ?? URLComponents()
        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "authuser", value: email))
        components.queryItems = queryItems
        return components.url ?? url
    }

    // MARK: - Private

    private static let meetingPatterns: [(pattern: String, provider: Provider)] = [
        (#"https?://[\w.-]*zoom\.us/j/\S+"#, .zoom),
        (#"https?://[\w.-]*zoom\.us/my/\S+"#, .zoom),
        (#"https?://teams\.microsoft\.com/l/meetup-join/\S+"#, .teams),
        (#"https?://teams\.live\.com/meet/\S+"#, .teams),
        (#"https?://meet\.google\.com/[\w-]+"#, .googleMeet),
        (#"https?://[\w.-]*webex\.com/\S+"#, .webex),
    ]

    private static func parse(url: URL) -> MeetingLink? {
        let urlString = url.absoluteString
        for (pattern, provider) in meetingPatterns {
            if urlString.range(of: pattern, options: .regularExpression) != nil {
                return MeetingLink(url: url, provider: provider)
            }
        }
        // If the URL doesn't match known providers but looks like a meeting link, still return it
        return nil
    }

    private static func findLink(in text: String) -> MeetingLink? {
        // Try known meeting patterns first
        for (pattern, provider) in meetingPatterns {
            if let range = text.range(of: pattern, options: .regularExpression) {
                let matched = String(text[range])
                if let url = URL(string: matched) {
                    return MeetingLink(url: url, provider: provider)
                }
            }
        }

        // Fallback: look for any https URL that might be a meeting link
        let urlPattern = #"https?://\S+"#
        if let range = text.range(of: urlPattern, options: .regularExpression) {
            let matched = String(text[range])
            // Clean trailing punctuation that might have been captured
            let cleaned = matched.trimmingCharacters(in: CharacterSet(charactersIn: ">,)\"'"))
            if let url = URL(string: cleaned) {
                let host = url.host?.lowercased() ?? ""
                // Only return if it looks like a meeting service, not random links
                let meetingHosts = ["zoom.us", "teams.microsoft.com", "teams.live.com",
                                    "meet.google.com", "webex.com", "whereby.com",
                                    "around.co", "meet.jit.si"]
                if meetingHosts.contains(where: { host.contains($0) }) {
                    return MeetingLink(url: url, provider: .unknown)
                }
            }
        }

        return nil
    }

    private static func zoomToNativeURL(_ webURL: URL) -> URL? {
        // Convert https://zoom.us/j/123456?pwd=xxx to zoommtg://zoom.us/join?confno=123456&pwd=xxx
        let urlString = webURL.absoluteString
        if let match = urlString.range(of: #"/j/(\d+)"#, options: .regularExpression) {
            let meetingID = urlString[match].replacingOccurrences(of: "/j/", with: "")
            var components = URLComponents()
            components.scheme = "zoommtg"
            components.host = "zoom.us"
            components.path = "/join"
            var queryItems = [URLQueryItem(name: "confno", value: meetingID)]
            if let pwd = URLComponents(url: webURL, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "pwd" })?.value {
                queryItems.append(URLQueryItem(name: "pwd", value: pwd))
            }
            components.queryItems = queryItems
            return components.url
        }
        return nil
    }

    private static func teamsToNativeURL(_ webURL: URL) -> URL? {
        // Teams deep link: msteams://l/meetup-join/...
        var components = URLComponents(url: webURL, resolvingAgainstBaseURL: false)
        components?.scheme = "msteams"
        return components?.url
    }

    private func launchNativeOrBrowser(
        nativeScheme: String,
        transform: (URL) -> URL?,
        fallback: URL
    ) {
        if let nativeURL = transform(url) {
            // Check if the native app can handle this URL scheme
            if NSWorkspace.shared.urlForApplication(toOpen: nativeURL) != nil {
                NSWorkspace.shared.open(nativeURL)
                return
            }
        }
        // Fallback to browser
        NSWorkspace.shared.open(fallback)
    }
}
