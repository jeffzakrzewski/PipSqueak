# PipSqueak

A tiny macOS menu bar app that nudges you into your next meeting.

**Latest release: 1.0.1**

PipSqueak watches your Calendar, counts down the time until your next meeting in the menu bar, and plays a gentle audio cue a few seconds before it starts so you actually show up on time.

## What it does

- **Countdown in the menu bar.** The time to your next meeting lives in your menu bar, always visible, no extra window to keep open. A compact mode shrinks it down when you'd rather have your real estate back.
- **Audio nudge before meetings.** Plays a configurable sound a chosen number of seconds before each meeting. Bring your own sound file if the default isn't your style.
- **Stays out of the way.** Respects Do Not Disturb — if DND is on, PipSqueak ducks the audio so it won't blast over a focus session.
- **Click to join.** Click a meeting in the popover to open its video link directly. Detects Google Meet, Zoom, and the usual suspects.
- **Multi-profile browser support.** If you live across multiple Chrome / Brave / Firefox profiles (work + personal), PipSqueak can route each meeting to the right profile so you don't land in the wrong Google account.
  > Note: per-profile launching is currently only verified against **Brave**. Chrome and Firefox are wired up but untested in the wild — please [file an issue](../../issues) if you hit problems on a different browser.
- **Calendar filtering.** Pick which calendars to watch, hide events without meeting links, or limit the view to today only.

## Requirements

- macOS 14.0 or later
- Calendar access (PipSqueak will ask the first time it runs)

## Installing

Download the latest `PipSqueak.dmg` from the [Releases page](../../releases/latest), open it, and drag PipSqueak into your Applications folder. Launch it once and grant Calendar access when prompted — the icon will appear in your menu bar.

To build from source instead, see below.

## Building from source

PipSqueak is a SwiftUI app generated via [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate
open PipSqueak.xcodeproj
```

Build and run the `PipSqueak` scheme in Xcode (⌘R). On first launch macOS will prompt for Calendar access.

### Project layout

```
PipSqueak/
  PipSqueakApp.swift        # App entry point (MenuBarExtra + Settings window)
  Managers/                 # Calendar, audio, countdown, browser-profile state
  Models/                   # MeetingEvent
  Views/                    # Menu bar popover + Settings tabs
  Resources/                # Default audio cue
audio/                      # Source audio assets
docs/plans/                 # Feature design docs
project.yml                 # XcodeGen spec
```

State is held in a single `AppState` (`@Observable`) and threaded through SwiftUI's `environment`. User preferences persist via `UserDefaults`; custom audio files persist via security-scoped bookmarks so they survive sandboxing across launches.

### Regenerating the Xcode project

Any time you add or remove a source file, regenerate:

```sh
xcodegen generate
```

## License

PipSqueak is released under the [MIT License](LICENSE).
