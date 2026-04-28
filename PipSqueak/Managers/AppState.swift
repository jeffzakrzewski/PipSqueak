import AppKit
import EventKit
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
        didSet {
            UserDefaults.standard.set(leadInDuration, forKey: "leadInDuration")
            countdownManager.leadInDuration = Int(leadInDuration)
        }
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
        didSet {
            UserDefaults.standard.set(compactMenuBar, forKey: "compactMenuBar")
            countdownManager.compact = compactMenuBar
        }
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
    private var isStarted = false
    private var wakeObserver: (any NSObjectProtocol)?
    private var clockChangeObserver: (any NSObjectProtocol)?
    private var didBecomeActiveObserver: (any NSObjectProtocol)?
    private var lastKnownAuthStatus: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)

    init() {
        // Load persisted values
        let defaults = UserDefaults.standard
        var loadedLeadIn = defaults.object(forKey: "leadInDuration") as? Double ?? 30
        // Normalize legacy 60s lead-in — option removed; clamp to 30.
        if loadedLeadIn == 60 { loadedLeadIn = 30 }
        self.leadInDuration = loadedLeadIn
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
        countdownManager.compact = compactMenuBar
        countdownManager.leadInDuration = Int(leadInDuration)

        // Audio scheduling callback fires on every countdown tick.
        countdownManager.onTick = { [weak self] in
            self?.scheduleAudioIfNeeded()
        }

        if !customAudioBookmarkData.isEmpty {
            audioManager.loadCustomAudio(bookmark: customAudioBookmarkData) { [weak self] regeneratedBookmark in
                guard let self, let regeneratedBookmark else { return }
                self.customAudioBookmarkData = regeneratedBookmark
            }
        } else {
            audioManager.loadBundledAudio()
        }
    }

    func start() async {
        guard !isStarted else { return }
        isStarted = true

        audioManager.setup()
        await browserProfileManager.detectBrowser()
        calendarManager.onCalendarChanged = { [weak self] in
            self?.refreshEvents()
        }
        calendarManager.startObservingChanges()
        countdownManager.startObserving()

        // Centralized wake / clock-change / app-activation observers.
        observeSystemEvents()

        await calendarManager.requestAccess()
        lastKnownAuthStatus = calendarManager.authorizationStatus

        if calendarManager.authorizationStatus == .fullAccess {
            refreshEvents()
            startRefreshLoop()
        }
    }

    /// Called by views (e.g. PermissionDeniedView) after a successful access grant.
    func onPermissionGranted() {
        guard calendarManager.authorizationStatus == .fullAccess else { return }
        calendarManager.loadCalendars()
        refreshEvents()
        startRefreshLoop()
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

    func scheduleAudioIfNeeded() {
        // Note: Focus state cannot be reliably queried by third-party apps on
        // macOS 12+; DND/Focus suppression is not implemented.
        guard let meeting = countdownManager.currentMeeting else {
            audioManager.cancelPlayback()
            return
        }

        let secondsUntilMeeting = meeting.startDate.timeIntervalSinceNow
        let leadIn = leadInDuration

        // If we previously scheduled for a different meeting (or different start),
        // cancel that schedule before deciding what to do for the current meeting.
        if let scheduledID = audioManager.scheduledMeetingID,
           scheduledID != meeting.id || audioManager.scheduledMeetingStartDate != meeting.startDate {
            audioManager.cancelPlayback()
        }

        guard secondsUntilMeeting > 0 else { return }

        if secondsUntilMeeting <= leadIn + 5 {
            audioManager.schedulePlayback(for: meeting, leadInSeconds: leadIn)
        }
    }

    // MARK: - Centralized system observers

    private func observeSystemEvents() {
        // Wake from sleep: refresh everything (cascades to countdown + audio scheduling).
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshEvents()
            }
        }

        // System clock changed (NTP update, manual change, timezone shift):
        // cancel any pending audio and re-schedule against the new clock.
        clockChangeObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name.NSSystemClockDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.audioManager.cancelPlayback()
                self.refreshEvents()
            }
        }

        // App activation: re-check calendar authorization in case the user
        // granted access in System Settings while we were backgrounded.
        didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleDidBecomeActive()
            }
        }
    }

    private func handleDidBecomeActive() {
        let changed = calendarManager.recheckAuthorization()
        let current = calendarManager.authorizationStatus
        if changed && current == .fullAccess {
            refreshEvents()
            startRefreshLoop()
        }
        lastKnownAuthStatus = current
    }
}
