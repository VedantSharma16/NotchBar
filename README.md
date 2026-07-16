# NotchBar

A free, open source Dynamic Island for the MacBook notch. Hover over the notch and it expands into a small control center with music controls, timers, a file shelf, and live system indicators. Similar to NotchNook, but free.

Built with Swift and SwiftUI as a plain Swift package. There is no Xcode project. It builds with the Command Line Tools alone.

## Features

- Now playing from Apple Music or Spotify: album art, play/pause/skip, a draggable seek bar, and scrolling text for long titles. Clicking the song opens the player app. While music plays, the collapsed notch shows the artwork and a small equalizer.
- File shelf: drag files onto the notch from anywhere, collect them, then share the whole batch over AirDrop, Messages, WhatsApp, or any other share extension. The shelf survives restarts.
- Live activities on the notch:
  - charger plugged in or out, with a low battery warning
  - AirPods and other audio output changes
  - microphone and camera in-use indicators
  - countdown timers, with the remaining time ticking on the notch
  - optional delivery tracking that surfaces delivery, ride, and flight notifications (off by default, see Permissions)
- System volume slider. The speaker icon reflects the actual output device (AirPods, Beats, speakers, AirPlay).
- Five animated gradient backgrounds, or use your own image. Set from the menu bar icon.
- Clicks outside the visible island pass through to whatever is underneath, so the menu bar stays fully usable.

## Requirements

- macOS 14 or newer (built and tested on macOS 26)
- A notch is optional. On Macs without one, and on external displays, it draws a small floating island instead.

## Build and run

```bash
git clone https://github.com/VedantSharma16/NotchBar.git
cd NotchBar
APP_NAME=NotchBar BUNDLE_ID=com.vedant.notchbar MENU_BAR_APP=1 SIGNING_MODE=adhoc Scripts/package_app.sh release
open NotchBar.app
```

For development, `swift build` gives fast incremental compiles.

The build is ad-hoc signed, so it runs on the machine that built it. Distributing binaries to other people requires a Developer ID certificate and notarization. `Scripts/sign-and-notarize.sh` has the plumbing for that.

## Permissions

NotchBar asks only for what a feature needs, when it needs it.

| Permission | When | Why |
|---|---|---|
| Automation (Music/Spotify) | First time it reads now-playing | AppleScript is the only supported way to read and control players since Apple locked down the private MediaRemote framework |
| Full Disk Access | Only if you enable Delivery Tracking | The macOS notification store is FDA-protected. Parsing is done entirely on-device and keyword-filtered. Nothing is stored or uploaded. The app works fully without it |

There are no analytics and no network calls, except fetching Spotify album art. Media control runs through in-process NSAppleScript, so the app never spawns subprocesses.

## Architecture notes

- `NotchPanel`: borderless, non-activating `NSPanel` floating above the menu bar on all Spaces. A custom `hitTest` makes everything outside the visible island click-through.
- `ActivityCenter`: single arbiter for what the collapsed notch shows (keyed, prioritized, auto-expiring activities).
- `MediaController`: cached, main-thread `NSAppleScript` bridge to Music and Spotify.
- `SystemEventsMonitor`: event-driven IOKit (battery) and CoreAudio (output device) listeners, with light 2s polling for mic and camera state.
- All animations (marquee, equalizer, countdowns, pulses) are clock-driven through `TimelineView`, which keeps them cheap and immune to re-render glitches.

See [DESIGN-v2-activities.md](DESIGN-v2-activities.md) for the activity system design notes.

## License

[MIT](LICENSE)
