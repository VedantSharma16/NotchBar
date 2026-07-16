# NotchBar v2 — Live Activities & Polish

## Understanding (confirmed 2026-07-16)

Evolve NotchBar into a live-activity hub with delight polish, keeping the
default install permission-free. Four activity sources: system events
(charger/battery/AirPods), privacy indicators (mic/camera in use),
timers with live countdown, and opt-in notification mirroring for
delivery/ride tracking. Polish: event animations, animated gradient
backgrounds, proximity "breathing". Explicitly no sound effects, no
system HUD replacement, no external service APIs, no settings window.

## Decision Log

| Decision | Alternatives | Why |
|---|---|---|
| Central `ActivityCenter` with keyed, prioritized, optionally-expiring activities | Per-feature ad-hoc UI state | One arbiter for the collapsed notch; features stay decoupled |
| Single current activity shown (priority, then recency) | Stacking/carousel UI | YAGNI; collapsed notch has room for exactly one story |
| Battery via IOKit power-source run-loop callback; audio device via CoreAudio listener | Polling | Event-driven ≈ zero idle cost |
| Mic/camera via `DeviceIsRunningSomewhere` polled every 2 s | CoreMediaIO listeners | Same public data, far less plumbing; 2 s latency fine for an indicator |
| Notification mirroring reads the macOS notification store (sqlite) — **opt-in**, FDA-gated, keyword-filtered, local-only | Accessibility scraping; skip feature | User-specified: app fully works without FDA; auto-activates when granted |
| Keyword filter (delivery/ride/flight/package terms) hardcoded v1 | Per-app allowlist | Smallest privacy surface; editable later |
| Mirrored activities transient (~60 s) | Persistent until dismissed | Notch is a glance surface, not an inbox |
| Timer state lives in its own manager; countdown rendered by TimelineView | Activity text updated every second | Reuses the deterministic-clock pattern that fixed the marquee |
| Animated backgrounds = hue/scale drift over existing gradients, expanded-only | Shader/video backgrounds | Cheap, battery-safe, no assets |
| Proximity breathing via 0.15 s mouse-location poll while collapsed | Global event monitor | No extra permissions, trivial cost, easy to reason about |

## Assumptions

- Idle cost budget: near-zero; nothing polls faster than 2 s except the
  8 Hz proximity check (a single `NSEvent.mouseLocation` read).
- Music remains the default resident of the collapsed wings; activities
  temporarily take over the right wing.
- Notification store schema (`record` table, binary-plist `data`) is
  undocumented; the mirror must fail silently and harmlessly if it changes.

## Component map

- `ActivityCenter.swift` — activity model + arbiter (keyed post/remove, expiry purge)
- `SystemEventsMonitor.swift` — battery/charger, output-device change, mic/camera indicators
- `NotchTimer.swift` — timer manager; posts "Time's up" activity
- `NotificationMirror.swift` — FDA detection, sqlite polling, keyword filter → activities
- UI: collapsed wings render current activity/countdown; slim activity banner row in expanded card; animated preset backgrounds; proximity breathe
