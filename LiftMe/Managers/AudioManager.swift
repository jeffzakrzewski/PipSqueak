import AppKit
import AVFoundation
import Foundation
import UniformTypeIdentifiers

@MainActor
@Observable
final class AudioManager {
    var isPlaying: Bool = false
    var volume: Float = 0.7
    var isAudioLoaded: Bool = false
    var audioDuration: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var customAudioBookmark: Data?
    private var wakeObserver: (any NSObjectProtocol)?
    private var scheduledMeetingID: String?

    // The audio is 33 seconds total:
    // - 0:00 to 0:30 = countdown (30 seconds)
    // - 0:30 = the pips hit (T=0, meeting starts)
    // - 0:30 to 0:33 = tail-off
    // So playback starts 30 seconds before meeting time.
    private let pipsOffset: TimeInterval = 30.0

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
        guard scheduledMeetingID != meeting.id else { return }

        let secondsUntilMeeting = meeting.startDate.timeIntervalSinceNow

        // Calculate when to start playback so pips hit at meeting start
        let playbackStartOffset = secondsUntilMeeting - pipsOffset

        if playbackStartOffset <= 0 && secondsUntilMeeting > 0 {
            // We're within the audio window -- start partway through
            player.currentTime = pipsOffset - secondsUntilMeeting
            player.volume = volume
            player.play()
            isPlaying = true
            scheduledMeetingID = meeting.id
        } else if playbackStartOffset > 0 && playbackStartOffset <= leadInSeconds {
            // Schedule future playback using hardware clock
            player.currentTime = 0
            player.volume = volume
            let playTime = player.deviceCurrentTime + playbackStartOffset + 0.01
            player.play(atTime: playTime)
            isPlaying = true
            scheduledMeetingID = meeting.id
        }
    }

    func cancelPlayback() {
        player?.stop()
        player?.currentTime = 0
        isPlaying = false
        scheduledMeetingID = nil
    }

    func updateVolume(_ newVolume: Float) {
        volume = newVolume
        player?.volume = newVolume
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
