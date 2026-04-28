import AppKit
import AVFoundation
import Foundation
import UniformTypeIdentifiers

@MainActor
@Observable
final class AudioManager: NSObject {
    enum DuckLevel {
        case full, ducked, muted

        var next: DuckLevel {
            switch self {
            case .full: return .ducked
            case .ducked: return .muted
            case .muted: return .muted
            }
        }
    }

    var isPlaying: Bool = false
    var volume: Float = 0.7
    var isAudioLoaded: Bool = false
    var audioDuration: TimeInterval = 0
    private(set) var duckLevel: DuckLevel = .full

    private var player: AVAudioPlayer?
    private var customAudioBookmark: Data?
    private var wakeObserver: (any NSObjectProtocol)?
    private var scheduledMeetingID: String?
    private var scheduledMeetingStartDate: Date?

    // The audio is 33 seconds total:
    // - 0:00 to 0:30 = countdown (30 seconds)
    // - 0:30 = the pips hit (T=0, meeting starts)
    // - 0:30 to 0:33 = tail-off
    // So playback starts 30 seconds before meeting time.
    private let pipsOffset: TimeInterval = 30.0
    private let duckedFactor: Float = 0.2

    func setup() {
        loadBundledAudio()
        observeWake()
    }

    func cleanup() {
        if let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            wakeObserver = nil
        }
    }

    func loadBundledAudio() {
        guard let url = Bundle.main.url(forResource: "30second", withExtension: "mp3") else {
            isAudioLoaded = false
            return
        }
        loadAudio(from: url)
    }

    func loadCustomAudio(bookmark: Data) {
        customAudioBookmark = bookmark
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, bookmarkDataIsStale: &isStale) else {
            loadBundledAudio()
            return
        }

        if isStale {
            loadBundledAudio()
            return
        }

        guard url.startAccessingSecurityScopedResource() else {
            loadBundledAudio()
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        loadAudio(from: url)
    }

    func selectCustomAudio() -> Data? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mp3, .mpeg4Audio, .wav, .aiff]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select a countdown audio file"

        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        guard let bookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return nil }

        loadCustomAudio(bookmark: bookmark)
        return bookmark
    }

    func schedulePlayback(for meeting: MeetingEvent, leadInSeconds: TimeInterval, isDNDActive: Bool) {
        guard !isDNDActive else { return }
        guard let player = player else { return }

        // If already scheduled for this exact meeting+time, skip
        if scheduledMeetingID == meeting.id && scheduledMeetingStartDate == meeting.startDate {
            return
        }

        // Meeting changed or was rescheduled -- cancel and re-schedule
        if scheduledMeetingID != nil {
            cancelPlayback()
        }

        // Defensive: any stale duck state from a prior playback that ended
        // without a clean cancel/finish path is wiped before we start fresh.
        resetDuckState()

        let secondsUntilMeeting = meeting.startDate.timeIntervalSinceNow
        guard secondsUntilMeeting > 0 else { return }

        // How many seconds before the meeting should audio start?
        // Use the shorter of: configured lead-in, or the pips offset (audio length to pips)
        let effectiveLeadIn = min(leadInSeconds, pipsOffset)

        // Audio should start at T - effectiveLeadIn
        let secondsUntilPlaybackStart = secondsUntilMeeting - effectiveLeadIn

        let shouldFadeIn = effectiveLeadIn > 2

        if secondsUntilPlaybackStart > 1 {
            // Schedule future playback using hardware clock for precise timing
            let audioStartPosition = pipsOffset - effectiveLeadIn
            player.currentTime = audioStartPosition
            player.volume = shouldFadeIn ? 0 : volume
            let playTime = player.deviceCurrentTime + secondsUntilPlaybackStart
            player.play(atTime: playTime)
            isPlaying = true
            scheduledMeetingID = meeting.id
            scheduledMeetingStartDate = meeting.startDate
            if shouldFadeIn {
                // Use AVAudioPlayer's native fade -- schedule it to start when playback begins
                DispatchQueue.main.asyncAfter(deadline: .now() + secondsUntilPlaybackStart) { [weak self] in
                    guard let self, self.isPlaying else { return }
                    self.player?.setVolume(self.volume, fadeDuration: 2.0)
                }
            }
        } else if secondsUntilPlaybackStart <= 1 && secondsUntilMeeting > 0 {
            // We're at or past the scheduled start -- play immediately from the right position
            let audioPosition = pipsOffset - secondsUntilMeeting
            player.currentTime = max(0, audioPosition)
            if shouldFadeIn {
                player.volume = 0
                player.play()
                player.setVolume(volume, fadeDuration: 2.0)
            } else {
                player.volume = volume
                player.play()
            }
            isPlaying = true
            scheduledMeetingID = meeting.id
            scheduledMeetingStartDate = meeting.startDate
        }
    }

    func cancelPlayback() {
        player?.stop()
        player?.currentTime = 0
        finishPlayback()
    }

    func updateVolume(_ newVolume: Float) {
        volume = newVolume
        player?.volume = newVolume
    }

    /// Advance the duck state one step (full → ducked → muted → muted) and
    /// apply the resulting volume directly to the underlying player without
    /// touching `self.volume`. No-op when audio is not currently playing.
    func advanceDuckIfPlaying() {
        guard isPlaying else { return }
        duckLevel = duckLevel.next
        switch duckLevel {
        case .full:
            player?.volume = volume
        case .ducked:
            player?.volume = volume * duckedFactor
        case .muted:
            player?.volume = 0
        }
    }

    private func resetDuckState() {
        duckLevel = .full
        player?.volume = volume
    }

    private func finishPlayback() {
        isPlaying = false
        scheduledMeetingID = nil
        scheduledMeetingStartDate = nil
        resetDuckState()
    }

    func previewAudio() {
        guard let player = player else { return }
        player.currentTime = 0
        player.volume = volume
        player.play()
        isPlaying = true
    }

    private func loadAudio(from url: URL) {
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.prepareToPlay()
            isAudioLoaded = true
            audioDuration = player?.duration ?? 0
        } catch {
            isAudioLoaded = false
            audioDuration = 0
            player = nil
        }
    }

    private func observeWake() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.isPlaying {
                    self.cancelPlayback()
                }
            }
        }
    }
}

extension AudioManager: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.finishPlayback()
        }
    }
}
