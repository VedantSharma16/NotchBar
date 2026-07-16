# NotchBar

A free, open-source Dynamic Island for the MacBook notch. Hover the notch and it expands into a control center: music, timers, file sharing, and live system activities — like NotchNook, but free and yours to hack on.

Built with Swift + SwiftUI as a pure Swift Package — **no Xcode project required**, builds with Command Line Tools alone.

## Features

🎵 **Music** — now playing from Apple Music or Spotify with album art, play/pause/skip, a live draggable seek bar, and marquee scrolling for long titles. Click the song to jump to the source app. While playing, the collapsed notch shows the artwork and an animated equalizer.

📁 **File shelf** — drag files onto the notch from anywhere, collect them, then share the whole batch at once via AirDrop, Messages, WhatsApp, or any share extension. Persists across restarts.

⚡ **Live activities** — the notch reacts to your Mac:
- Charger plugged/unplugged (bolt + battery %), low-battery pulse
- AirPods or output device changes (device-specific icons)
- Mic/camera in-use privacy indicators
- Countdown timers with the remaining time ticking on the notch
- **Delivery tracking (opt-in beta)** — mirrors delivery/ride/flight notifications as notch activities

🔊 **Volume** — system volume slider with an icon that reflects your actual output device (AirPods, AirPods Max, Beats, speakers, AirPlay…).

🎨 **Backgrounds** — five animated abstract gradients or your own image, from the menu bar icon.

✨ **Feel** — spring animations, proximity "breathing" as your cursor approaches, pass-through clicks (the invisible parts of the window never block your menu bar).

## Requirements

- macOS 14+ (built and tested on macOS 26)
- A notch is optional — on notch-less Macs and external displays it draws a small floating island instead

## Build & run

```bash
git clone https://github.com/VedantSharma16/NotchBar.git
cd NotchBar
APP_NAME=NotchBar BUNDLE_ID=com.vedant.notchbar MENU_BAR_APP=1 SIGNING_MODE=adhoc Scripts/package_app.sh release
open NotchBar.app
```

For development, `swift build` gives you fast incremental compiles.

The build is ad-hoc signed, so it runs on your own machine. To distribute binaries to others you'd need a Developer ID certificate and notarization (`Scripts/sign-and-notarize.sh` has the plumbing).

## Permissions

NotchBar asks only for what a feature needs, when it needs it:

| Permission | When | Why |
|---|---|---|
| Automation (Music/Spotify) | First time it reads now-playing | AppleScript is the only supported way to read/control players since Apple locked down the private MediaRemote framework |
| Full Disk Access | **Only** if you enable Delivery Tracking | The macOS notification store is FDA-protected. Parsing is 100% on-device, keyword-filtered, nothing stored or uploaded. The app works fully without it |

There are no analytics, no network calls except fetching Spotify album art, and no subprocess spawning — media control runs via in-process `NSAppleScript`.

## Architecture notes

- `NotchPanel` — borderless, non-activating `NSPanel` floating above the menu bar on all Spaces; a custom `hitTest` makes everything outside the visible island click-through
- `ActivityCenter` — single arbiter for what the collapsed notch shows (keyed, prioritized, auto-expiring activities)
- `MediaController` — cached, main-thread `NSAppleScript` bridge to Music/Spotify
- `SystemEventsMonitor` — event-driven IOKit (battery) + CoreAudio (output device) listeners; gentle 2s polling for mic/camera state
- Animations (marquee, equalizer, countdowns, pulses) are all clock-driven via `TimelineView` — deterministic, cheap, and immune to re-render glitches

See [DESIGN-v2-activities.md](DESIGN-v2-activities.md) for the activity-system design and decision log.

## License

[MIT](LICENSE)
