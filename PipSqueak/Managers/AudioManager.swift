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

    enum AudioStatus: Equatable {
        case ok
        case fallbackToBundled(String)
        case failed(String)
    }

    var isPlaying: Bool = false
    var volume: Float = 0.7
    var isMuted: Bool = false
    var isAudioLoaded: Bool = false
    var audioDuration: TimeInterval = 0
    var audioStatus: AudioStatus = .ok
    private(set) var duckLevel: DuckLevel = .full

    /// Exposed for AppState's stale-meeting cancellation logic.
    private(set) var scheduledMeetingID: String?
    private(set) var scheduledMeetingStartDate: Date?

    private var player: AVAudioPlayer?
    private var customAudioBookmark: Data?
    private var pendingFadeWork: DispatchWorkItem?

    /// Effective player volume — accounts for the user's mute toggle without
    /// destroying the underlying volume value.
    private var effectiveVolume: Float {
        isMuted ? 0 : volume
    }

    // The audio is 33 seconds total:
    // - 0:00 to 0:30 = countdown (30 seconds)
    // - 0:30 = the pips hit (T=0, meeting starts)
    // - 0:30 to 0:33 = tail-off
    // So playback starts 30 seconds before meeting time.
    private let pipsOffset: TimeInterval = 30.0
    private let duckedFactor: Float = 0.2

    func setup() {
        loadBundledAudio()
    }

    func cleanup() {
        // Wake observation lives in AppState now; nothing to tear down here.
    }

    func loadBundledAudio() {
        guard let url = Bundle.main.url(forResource: "30second", withExtension: "mp3") else {
            isAudioLoaded = false
            audioStatus = .failed("Bundled audio file is missing.")
            return
        }
        if loadAudio(from: url) {
            // Only mark .ok if we weren't already showing a fallback message
            // from an earlier failed custom-audio load.
            if case .fallbackToBundled = audioStatus {
                // Preserve the fallback note so the user sees why we reverted.
            } else {
                audioStatus = .ok
            }
        } else {
            audioStatus = .failed("Failed to load bundled audio.")
        }
    }

    /// Load a custom audio file from a security-scope-free bookmark. If the
    /// bookmark is stale, the closure is called with regenerated bookmark data
    /// so the caller (AppState) can persist the refreshed bookmark.
    func loadCustomAudio(bookmark: Data, regeneratedBookmark: ((Data?) -> Void)? = nil) {
        customAudioBookmark = bookmark
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [], bookmarkDataIsStale: &isStale) else {
            audioStatus = .fallbackToBundled("Could not resolve saved audio bookmark; using bundled sound.")
            loadBundledAudio()
            return
        }

        if isStale {
            // Try to regenerate the bookmark from the resolved URL before
            // falling back. This handles ordinary file moves transparently.
            if let regenerated = try? url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                customAudioBookmark = regenerated
                regeneratedBookmark?(regenerated)
                if loadAudio(from: url) {
                    audioStatus = .ok
                    return
                }
            }
            audioStatus = .fallbackToBundled("Saved audio location changed; using bundled sound.")
            loadBundledAudio()
            return
        }

        if loadAudio(from: url) {
            audioStatus = .ok
        } else {
            audioStatus = .fallbackToBundled("Failed to load custom audio file; using bundled sound.")
            loadBundledAudio()
        }
    }

    /// Load custom audio directly from a URL the view layer obtained via NSOpenPanel.
    func loadCustomAudio(from url: URL) -> Data? {
        guard let bookmark = try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            audioStatus = .failed("Could not create bookmark for selected file.")
            return nil
        }
        customAudioBookmark = bookmark
        if loadAudio(from: url) {
            audioStatus = .ok
            return bookmark
        } else {
            audioStatus = .fallbackToBundled("Failed to load selected audio file; using bundled sound.")
            loadBundledAudio()
            return nil
        }
    }

    func schedulePlayback(for meeting: MeetingEvent, leadInSeconds: TimeInterval) {
        guard let player = player else { return }

        // If already scheduled for this exact meeting+time, skip
        if scheduledMeetingID == meeting.id && scheduledMeetingStartDate == meeting.startDate {
            return
        }

        // Meeting changed or was rescheduled -- cancel and re-schedule
        if scheduledMeetingID != nil {
            cancelPlayback()
        }

        // Cancel any prior pending fade work before scheduling fresh.
        pendingFadeWork?.cancel()
        pendingFadeWork = nil

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
            player.volume = shouldFadeIn ? 0 : effectiveVolume
            let playTime = player.deviceCurrentTime + secondsUntilPlaybackStart
            player.play(atTime: playTime)
            isPlaying = true
            scheduledMeetingID = meeting.id
            scheduledMeetingStartDate = meeting.startDate
            if shouldFadeIn {
                // Use AVAudioPlayer's native fade -- schedule it via a cancellable work item
                let work = DispatchWorkItem { [weak self] in
                    guard let self, self.isPlaying else { return }
                    self.player?.setVolume(self.effectiveVolume, fadeDuration: 2.0)
                }
                pendingFadeWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + secondsUntilPlaybackStart, execute: work)
            }
        } else if secondsUntilPlaybackStart <= 1 && secondsUntilMeeting > 0 {
            // We're at or past the scheduled start -- play immediately from the right position
            let audioPosition = pipsOffset - secondsUntilMeeting
            player.currentTime = max(0, audioPosition)
            if shouldFadeIn {
                player.volume = 0
                player.play()
                player.setVolume(effectiveVolume, fadeDuration: 2.0)
            } else {
                player.volume = effectiveVolume
                player.play()
            }
            isPlaying = true
            scheduledMeetingID = meeting.id
            scheduledMeetingStartDate = meeting.startDate
        }
    }

    func cancelPlayback() {
        pendingFadeWork?.cancel()
        pendingFadeWork = nil
        player?.stop()
        player?.currentTime = 0
        finishPlayback()
    }

    func updateVolume(_ newVolume: Float) {
        volume = newVolume
        player?.volume = effectiveVolume
    }

    /// Advance the duck state one step (full → ducked → muted → muted) and
    /// apply the resulting volume directly to the underlying player without
    /// touching `self.volume`. No-op when audio is not currently playing.
    func advanceDuckIfPlaying() {
        guard isPlaying else { return }
        duckLevel = duckLevel.next
        switch duckLevel {
        case .full:
            player?.volume = effectiveVolume
        case .ducked:
            player?.volume = effectiveVolume * duckedFactor
        case .muted:
            player?.volume = 0
        }
    }

    private func resetDuckState() {
        duckLevel = .full
        player?.volume = effectiveVolume
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
        player.volume = effectiveVolume
        player.play()
        isPlaying = true
    }

    /// Returns true on success.
    @discardableResult
    private func loadAudio(from url: URL) -> Bool {
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.prepareToPlay()
            isAudioLoaded = true
            audioDuration = player?.duration ?? 0
            return true
        } catch {
            isAudioLoaded = false
            audioDuration = 0
            player = nil
            return false
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
