import AppKit
import SwiftUI

struct MenuBarLabel: View {
    @Environment(AppState.self) private var appState
    @State private var flashOn = false
    @State private var justStartedMeeting = false
    @State private var pendingFlashWork: [DispatchWorkItem] = []

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
        .accessibilityLabel("PipSqueak — \(appState.menuBarTitle)")
        .onChange(of: remaining) { _, secs in
            cancelPendingFlashWork()
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
            cancelPendingFlashWork()
            if case .inMeeting = newState {
                if case .upcoming = oldState {
                    flashOn = false
                    justStartedMeeting = true
                    updateStatusItemBackground(color: .systemGreen)
                    let work = DispatchWorkItem {
                        justStartedMeeting = false
                        updateStatusItemBackground(color: nil)
                    }
                    pendingFlashWork.append(work)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
                }
            }
        }
        .task {
            await appState.start()
        }
    }

    private func cancelPendingFlashWork() {
        for work in pendingFlashWork {
            work.cancel()
        }
        pendingFlashWork.removeAll()
    }

    /// Flash ON at each interval offset, OFF halfway between each
    private func flashCycle(intervals: [Double], within secs: Int) {
        let halfGap = intervals.count > 1
            ? (intervals[1] - intervals[0]) / 2.0
            : 0.25

        for offset in intervals {
            // ON
            let onWork = DispatchWorkItem {
                guard remaining == secs, !justStartedMeeting else { return }
                flashOn = true
                updateStatusItemBackground(color: .systemRed)
            }
            pendingFlashWork.append(onWork)
            DispatchQueue.main.asyncAfter(deadline: .now() + offset, execute: onWork)

            // OFF
            let offWork = DispatchWorkItem {
                guard remaining == secs, !justStartedMeeting else { return }
                flashOn = false
                updateStatusItemBackground(color: nil)
            }
            pendingFlashWork.append(offWork)
            DispatchQueue.main.asyncAfter(deadline: .now() + offset + halfGap, execute: offWork)
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

    /// Walks NSApp.windows looking for the NSStatusBar host window by class-name
    /// substring. Private-AppKit-shaped — class names and window-tree shape can
    /// change across macOS versions. If this returns nil the menu-bar flash
    /// silently no-ops; we log a warning the first time so future breakage is
    /// observable.
    private func findStatusItemButton() -> NSStatusBarButton? {
        for window in NSApp.windows {
            let windowClass = String(describing: type(of: window))
            if windowClass.contains("NSStatusBar") {
                if let button = findButton(in: window.contentView) {
                    return button
                }
            }
        }
        if !MenuBarLabelWarningState.didWarnLookupFailure {
            MenuBarLabelWarningState.didWarnLookupFailure = true
            print("[PipSqueak] Warning: findStatusItemButton failed; menu bar flash will not render. macOS NSStatusBar internals may have changed.")
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

@MainActor
private enum MenuBarLabelWarningState {
    static var didWarnLookupFailure = false
}
