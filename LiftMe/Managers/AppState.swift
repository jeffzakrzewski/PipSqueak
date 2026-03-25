import Foundation
import SwiftUI

@MainActor
@Observable
final class AppState {
    let calendarManager = CalendarManager()
    let countdownManager = CountdownManager()
    let audioManager = AudioManager()
    let browserProfileManager = BrowserProfileManager()

    // Observable properties that sync to UserDefaults
    var leadInDuration: Double {
        didSet { UserDefaults.standard.set(leadInDuration, forKey: "leadInDuration") }
    }

    var audioVolume: Double {
        didSet {
            UserDefaults.standard.set(audioVolume, forKey: "audioVolume")
            audioManager.updateVolume(Float(audioVolume))
        }
    }

    var customAudioBookmarkData: Data {
        didSet { UserDefaults.standard.set(customAudioBookmarkData, forKey: "customAudioBookmark") }
    }

    var launchAtLogin: Bool {
        didSet { UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin") }
    }

    var compactMenuBar: Bool {
        didSet { UserDefaults.standard.set(compactMenuBar, forKey: "compactMenuBar") }
    }

    var showEventsWithoutLinks: Bool {
        didSet {
            UserDefaults.standard.set(showEventsWithoutLinks, forKey: "showEventsWithoutLinks")
            refreshEvents()
        }
    }

    var onlyShowTodayEvents: Bool {
        didSet {
            UserDefaults.standard.set(onlyShowTodayEvents, forKey: "onlyShowTodayEvents")
            refreshEvents()
        }
    }

    var selectedCalendarIDs: Set<String> {
        didSet {
            let data = (try? JSONEncoder().encode(selectedCalendarIDs)) ?? Data()
            UserDefaults.standard.set(data, forKey: "selectedCalendarIDs")
        }
    }

    private var refreshTimer: Timer?

    init() {
        // Load persisted values
        let defaults = UserDefaults.standard
        self.leadInDuration = defaults.object(forKey: "leadInDuration") as? Double ?? 30
        self.audioVolume = defaults.object(forKey: "audioVolume") as? Double ?? 0.7
        self.customAudioBookmarkData = defaults.data(forKey: "customAudioBookmark") ?? Data()
        self.launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        self.compactMenuBar = defaults.bool(forKey: "compactMenuBar")
        self.showEventsWithoutLinks = defaults.bool(forKey: "showEventsWithoutLinks")
        self.onlyShowTodayEvents = defaults.bool(forKey: "onlyShowTodayEvents")

        if let calData = defaults.data(forKey: "selectedCalendarIDs"),
           let ids = try? JSONDecoder().decode(Set<String>.self, from: calData) {
            self.selectedCalendarIDs = ids
        } else {
            self.selectedCalendarIDs = []
        }

        audioManager.volume = Float(audioVolume)

        if !customAudioBookmarkData.isEmpty {
            audioManager.loadCustomAudio(bookmark: customAudioBookmarkData)
        } else {
            audioManager.loadBundledAudio()
        }
    }

    func start() async {
        audioManager.setup()
        calendarManager.startObservingChanges()
        countdownManager.startObserving()

        await calendarManager.requestAccess()

        if calendarManager.authorizationStatus == .fullAccess {
            refreshEvents()
            startRefreshLoop()
        }
    }

    func refreshEvents() {
        calendarManager.fetchUpcomingEvents(
            selectedCalendarIDs: selectedCalendarIDs,
            showEventsWithoutLinks: showEventsWithoutLinks,
            onlyToday: onlyShowTodayEvents
        )
        countdownManager.update(with: calendarManager.upcomingEvents)
        scheduleAudioIfNeeded()
    }

    func toggleCalendar(_ calendarID: String) {
        if selectedCalendarIDs.contains(calendarID) {
            selectedCalendarIDs.remove(calendarID)
        } else {
            selectedCalendarIDs.insert(calendarID)
        }
        refreshEvents()
    }

    func selectAllCalendars() {
        selectedCalendarIDs = Set(calendarManager.allCalendars.map { $0.calendarIdentifier })
        refreshEvents()
    }

    var menuBarTitle: String {
        countdownManager.compact = compactMenuBar
        return countdownManager.menuBarTitle
    }

    var menuBarIcon: String {
        countdownManager.menuBarIcon
    }

    private func startRefreshLoop() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshEvents()
            }
        }
        RunLoop.main.add(refreshTimer!, forMode: .common)
    }

    private func scheduleAudioIfNeeded() {
        guard let meeting = countdownManager.currentMeeting else {
            audioManager.cancelPlayback()
            return
        }

        let secondsUntilMeeting = meeting.startDate.timeIntervalSinceNow
        guard secondsUntilMeeting > 0 else { return }

        let isDND = isDNDActive()
        let leadIn = leadInDuration

        if secondsUntilMeeting <= leadIn + 5 {
            audioManager.schedulePlayback(for: meeting, leadInSeconds: leadIn, isDNDActive: isDND)
        }
    }

    private func isDNDActive() -> Bool {
        let dndDefaults = UserDefaults(suiteName: "com.apple.notificationcenterui")
        return dndDefaults?.bool(forKey: "doNotDisturb") ?? false
    }
}
