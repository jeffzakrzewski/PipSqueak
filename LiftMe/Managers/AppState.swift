import Foundation
import SwiftUI

@MainActor
@Observable
final class AppState {
    let calendarManager = CalendarManager()
    let countdownManager = CountdownManager()
    let audioManager = AudioManager()

    @ObservationIgnored
    @AppStorage("selectedCalendarIDs") private var selectedCalendarIDsData: Data = Data()

    @ObservationIgnored
    @AppStorage("leadInDuration") var leadInDuration: Double = 30

    @ObservationIgnored
    @AppStorage("audioVolume") var audioVolume: Double = 0.7

    @ObservationIgnored
    @AppStorage("customAudioBookmark") var customAudioBookmarkData: Data = Data()

    @ObservationIgnored
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false

    var selectedCalendarIDs: Set<String> {
        get {
            guard !selectedCalendarIDsData.isEmpty,
                  let ids = try? JSONDecoder().decode(Set<String>.self, from: selectedCalendarIDsData)
            else { return [] }
            return ids
        }
        set {
            selectedCalendarIDsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    private var refreshTimer: Timer?

    init() {
        audioManager.volume = Float(audioVolume)

        if !customAudioBookmarkData.isEmpty {
            audioManager.loadCustomAudio(bookmark: customAudioBookmarkData)
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
        calendarManager.fetchUpcomingEvents(selectedCalendarIDs: selectedCalendarIDs)
        countdownManager.update(with: calendarManager.upcomingEvents)
        scheduleAudioIfNeeded()
    }

    func toggleCalendar(_ calendarID: String) {
        var ids = selectedCalendarIDs
        if ids.contains(calendarID) {
            ids.remove(calendarID)
        } else {
            ids.insert(calendarID)
        }
        selectedCalendarIDs = ids
        refreshEvents()
    }

    func selectAllCalendars() {
        selectedCalendarIDs = Set(calendarManager.allCalendars.map { $0.calendarIdentifier })
        refreshEvents()
    }

    var menuBarTitle: String {
        countdownManager.menuBarTitle
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
