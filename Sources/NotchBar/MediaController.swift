import AppKit
import Foundation

struct NowPlaying: Equatable {
    enum Source: String {
        case spotify = "Spotify"
        case music = "Music"
    }

    var source: Source
    var title: String
    var artist: String
    var isPlaying: Bool
    var artworkURL: String?
    /// Playback position (seconds) at the moment `fetchedAt` was taken —
    /// the UI extrapolates forward from these for a smooth progress bar.
    var position: Double = 0
    var duration: Double = 0
    var fetchedAt: Date = .init()
}

/// Talks to Spotify / Apple Music via AppleScript (`osascript`).
/// The private MediaRemote framework is off-limits on modern macOS,
/// so scripting the players directly is the dependable approach.
final class MediaController: ObservableObject {
    @Published var nowPlaying: NowPlaying?
    @Published var artwork: NSImage?
    @Published var volume: Double = 0.5
    @Published var outputDevice: AudioOutput.Info = AudioOutput.fallback

    private var timer: Timer?
    private var artworkKey: String?
    private var pendingVolumeSet: DispatchWorkItem?

    private static let spotifyBundleID = "com.spotify.client"
    private static let musicBundleID = "com.apple.Music"

    func start() {
        poll()
        readVolume()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Polling

    private static func isRunning(_ bundleID: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
    }

    /// Runs on the main thread (NSAppleScript requirement); the player
    /// queries return in a few milliseconds.
    func poll() {
        var result: NowPlaying?

        if Self.isRunning(Self.spotifyBundleID) {
            result = querySpotify()
        }
        // Music wins only if Spotify has nothing, or Music is actively playing.
        if result == nil || result?.isPlaying == false {
            if Self.isRunning(Self.musicBundleID), let music = queryMusic() {
                if result == nil || music.isPlaying {
                    result = music
                }
            }
        }

        let output = AudioOutput.current()

        if nowPlaying != result {
            nowPlaying = result
        }
        if outputDevice != output {
            outputDevice = output
        }
        updateArtwork()
    }

    // NOTE: some short identifiers (e.g. `st`) collide with reserved AppleScript
    // terminology on recent macOS and cause silent syntax errors — keep variable
    // names long and descriptive in these scripts.
    private func querySpotify() -> NowPlaying? {
        let script = """
        tell application "Spotify"
            set stateText to player state as text
            if stateText is "stopped" then return "stopped"
            return stateText & "||" & (name of current track) & "||" & (artist of current track) & "||" & (artwork url of current track) & "||" & (player position as text) & "||" & (duration of current track as text)
        end tell
        """
        guard let out = Self.runAppleScript(script), out != "stopped", !out.isEmpty else { return nil }
        let parts = out.components(separatedBy: "||")
        guard parts.count >= 3 else { return nil }
        return NowPlaying(
            source: .spotify,
            title: parts[1],
            artist: parts[2],
            isPlaying: parts[0] == "playing",
            artworkURL: parts.count > 3 ? parts[3] : nil,
            position: parts.count > 4 ? Self.parseNumber(parts[4]) : 0,
            // Spotify reports duration in milliseconds.
            duration: parts.count > 5 ? Self.parseNumber(parts[5]) / 1000.0 : 0,
            fetchedAt: Date()
        )
    }

    private func queryMusic() -> NowPlaying? {
        let script = """
        tell application "Music"
            set stateText to player state as text
            if stateText is "stopped" then return "stopped"
            return stateText & "||" & (name of current track) & "||" & (artist of current track) & "||" & (player position as text) & "||" & (duration of current track as text)
        end tell
        """
        guard let out = Self.runAppleScript(script), out != "stopped", !out.isEmpty else { return nil }
        let parts = out.components(separatedBy: "||")
        guard parts.count >= 3 else { return nil }
        return NowPlaying(
            source: .music,
            title: parts[1],
            artist: parts[2],
            isPlaying: parts[0] == "playing",
            artworkURL: nil,
            position: parts.count > 3 ? Self.parseNumber(parts[3]) : 0,
            duration: parts.count > 4 ? Self.parseNumber(parts[4]) : 0,
            fetchedAt: Date()
        )
    }

    /// AppleScript renders decimals with the system locale's separator.
    private static func parseNumber(_ raw: String) -> Double {
        Double(raw.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    // MARK: - Transport controls

    /// Bring the app that's playing (Music / Spotify) to the front.
    func openPlayerApp() {
        guard let source = nowPlaying?.source else { return }
        let bundleID = source == .spotify ? Self.spotifyBundleID : Self.musicBundleID
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Jump to a position (seconds) in the current track.
    func seek(to seconds: Double) {
        guard var playing = nowPlaying else { return }
        // Optimistic local update so the bar doesn't snap back before the
        // next poll confirms the new position.
        playing.position = seconds
        playing.fetchedAt = Date()
        nowPlaying = playing

        let app = playing.source.rawValue
        Self.runAppleScript(
            "tell application \"\(app)\" to set player position to \(seconds)",
            cache: false
        )
        pollSoon()
    }

    /// Re-poll shortly after a command so the UI reflects the change.
    private func pollSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.poll()
        }
    }

    func playPause() { sendCommand("playpause") }
    func nextTrack() { sendCommand("next track") }
    func previousTrack() { sendCommand("previous track") }

    private func sendCommand(_ command: String) {
        guard let source = nowPlaying?.source else { return }
        Self.runAppleScript("tell application \"\(source.rawValue)\" to \(command)")
        pollSoon()
    }

    // MARK: - System volume

    func readVolume() {
        guard let out = Self.runAppleScript("output volume of (get volume settings)"),
              let value = Int(out) else { return }
        volume = Double(value) / 100.0
    }

    func setVolume(_ newValue: Double) {
        volume = newValue
        pendingVolumeSet?.cancel()
        let item = DispatchWorkItem {
            Self.runAppleScript("set volume output volume \(Int(newValue * 100))", cache: false)
        }
        pendingVolumeSet = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: item)
    }

    // MARK: - Artwork

    private func updateArtwork() {
        guard let playing = nowPlaying else {
            artwork = nil
            artworkKey = nil
            return
        }
        let key = "\(playing.source.rawValue)|\(playing.title)|\(playing.artist)"
        guard key != artworkKey else { return }
        artworkKey = key

        switch playing.source {
        case .spotify:
            loadSpotifyArtwork(key: key, urlString: playing.artworkURL)
        case .music:
            loadMusicArtwork(key: key)
        }
    }

    private func loadSpotifyArtwork(key: String, urlString: String?) {
        guard let urlString, let url = URL(string: urlString) else {
            artwork = nil
            return
        }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                // Only apply if the track hasn't changed underneath us.
                if self?.artworkKey == key {
                    self?.artwork = image
                }
            }
        }.resume()
    }

    /// Music has no artwork URL; ask it to write the raw artwork bytes to a
    /// temp file, then read the image back.
    private func loadMusicArtwork(key: String) {
        let path = NSTemporaryDirectory() + "notchbar_artwork"
        let script = """
        tell application "Music"
            if (count of artworks of current track) is 0 then return "none"
            set artworkData to data of artwork 1 of current track
        end tell
        set fileRef to open for access POSIX file "\(path)" with write permission
        set eof fileRef to 0
        write artworkData to fileRef
        close access fileRef
        return "ok"
        """
        let result = Self.runAppleScript(script)
        let image = result == "ok" ? NSImage(contentsOfFile: path) : nil
        if artworkKey == key {
            artwork = image
        }
    }

    // MARK: - AppleScript runner

    /// Executes AppleScript in-process via NSAppleScript instead of spawning
    /// `osascript` — no child processes (which security tools rightly flag),
    /// and static scripts are compiled once and reused. NSAppleScript is not
    /// thread-safe, so everything runs on the main thread.
    private static var scriptCache = [String: NSAppleScript]()

    @discardableResult
    private static func runAppleScript(_ source: String, cache: Bool = true) -> String? {
        assert(Thread.isMainThread, "NSAppleScript must run on the main thread")

        let script: NSAppleScript
        if cache, let cached = scriptCache[source] {
            script = cached
        } else {
            guard let fresh = NSAppleScript(source: source) else { return nil }
            if cache { scriptCache[source] = fresh }
            script = fresh
        }

        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        guard errorInfo == nil else { return nil }
        return result.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
