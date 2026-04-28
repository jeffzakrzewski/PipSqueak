import AppKit
import SwiftUI

struct MenuBarLabel: View {
    @Environment(AppState.self) private var appState
    @State private var flashOn = false
    @State private var justStartedMeeting = false

    private var remaining: Int {
        appState.countdownManager.remainingSeconds
    }

    private var isUrgent: Bool {
        remaining > 0 && remaining <= 10
    }

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: appState.menuBarIcon)
            if !appState.menuBarTitle.isEmpty {
                Text(" \(appState.menuBarTitle)")
                    .monospacedDigit()
            }
        }
        .onChange(of: remaining) { _, secs in
            guard secs > 0, secs <= 10 else {
                if !justStartedMeeting {
                    flashOn = false
                    updateStatusItemBackground(color: nil)
                }
                return
            }
            // Sync flash to each countdown tick
            if secs <= 2 {
                // Quarter-second flashing: ON-OFF-ON-OFF within each second
                flashCycle(intervals: [0, 0.25, 0.5, 0.75], within: secs)
            } else {
                // Half-second flashing: ON-OFF within each second
                flashCycle(intervals: [0, 0.5], within: secs)
            }
        }
        .onChange(of: appState.countdownManager.meetingState) { oldState, newState in
            if case .inMeeting = newState {
                if case .upcoming = oldState {
                    flashOn = false
                    justStartedMeeting = true
                    updateStatusItemBackground(color: .systemGreen)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        justStartedMeeting = false
                        updateStatusItemBackground(color: nil)
                    }
                }
            }
        }
        .task {
            await appState.start()
        }
    }

    /// Flash ON at each interval offset, OFF halfway between each
    private func flashCycle(intervals: [Double], within secs: Int) {
        let halfGap = intervals.count > 1
            ? (intervals[1] - intervals[0]) / 2.0
            : 0.25

        for offset in intervals {
            // ON
            DispatchQueue.main.asyncAfter(deadline: .now() + offset) {
                guard remaining == secs, !justStartedMeeting else { return }
                flashOn = true
                updateStatusItemBackground(color: .systemRed)
            }
            // OFF
            DispatchQueue.main.asyncAfter(deadline: .now() + offset + halfGap) {
                guard remaining == secs, !justStartedMeeting else { return }
                flashOn = false
                updateStatusItemBackground(color: nil)
            }
        }
    }

    private func updateStatusItemBackground(color: NSColor?) {
        DispatchQueue.main.async {
            guard let button = findStatusItemButton() else { return }
            button.wantsLayer = true
            if let color {
                button.layer?.backgroundColor = color.cgColor
                button.layer?.cornerRadius = 4
            } else {
                button.layer?.backgroundColor = nil
            }
        }
    }

    private func findStatusItemButton() -> NSStatusBarButton? {
        for window in NSApp.windows {
            let windowClass = String(describing: type(of: window))
            if windowClass.contains("NSStatusBar") {
                if let button = findButton(in: window.contentView) {
                    return button
                }
            }
        }
        return nil
    }

    private func findButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view = view else { return nil }
        if let button = view as? NSStatusBarButton {
            return button
        }
        for subview in view.subviews {
            if let button = findButton(in: subview) {
                return button
            }
        }
        return nil
    }
}
