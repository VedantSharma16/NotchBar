import SwiftUI
import UniformTypeIdentifiers

struct NotchView: View {
    @ObservedObject var state: NotchState
    @ObservedObject var media: MediaController
    @ObservedObject var shelf: FileShelf
    @ObservedObject var activities: ActivityCenter
    @ObservedObject var timers: NotchTimerManager

    @State private var collapseTask: DispatchWorkItem?
    @State private var isDropTargeted = false
    @State private var isSongHovered = false
    @State private var isScrubbing = false
    @State private var scrubPosition: Double = 0

    private var islandSize: CGSize {
        state.isExpanded ? state.expandedSize : state.collapsedSize
    }

    var body: some View {
        ZStack(alignment: .top) {
            island
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var islandShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            bottomLeadingRadius: state.isExpanded ? 18 : 10,
            bottomTrailingRadius: state.isExpanded ? 18 : 10
        )
    }

    private var openSpring: Animation {
        .spring(response: 0.45, dampingFraction: 0.74)
    }

    /// Closing is tighter and bounce-free: overshoot reads as playful on
    /// the way out but as jitter when snapping back into the notch.
    private var closeSpring: Animation {
        .spring(response: 0.32, dampingFraction: 0.92)
    }

    private var island: some View {
        ZStack(alignment: .top) {
            islandShape
                .fill(.black)
                .shadow(color: .black.opacity(state.isExpanded ? 0.4 : 0), radius: 10, y: 4)

            if state.isExpanded, state.background != .plain {
                backgroundLayer
                    .frame(width: islandSize.width, height: islandSize.height)
                    .clipShape(islandShape)
                    // Fade in gently once the shape is opening, but vanish
                    // almost instantly on collapse: if it fades on the same
                    // spring as the shrinking shape, it hangs visibly past
                    // the island's edge for a few frames.
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.easeOut(duration: 0.25).delay(0.05)),
                        removal: .opacity.animation(.easeOut(duration: 0.06))
                    ))
            }

            if state.isExpanded {
                expandedContent
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top))
                            .animation(.easeOut(duration: 0.22).delay(0.08)),
                        removal: .opacity.animation(.easeIn(duration: 0.1))
                    ))
            } else if state.hasActivity {
                collapsedActivity
                    .transition(.opacity)
            }
        }
        .frame(width: islandSize.width, height: islandSize.height)
        .animation(state.isExpanded ? openSpring : closeSpring, value: state.isExpanded)
        .animation(openSpring, value: state.hasActivity)
        .animation(openSpring, value: state.rightWingWidth)
        .animation(openSpring, value: state.showsActivityBanner)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: state.isNear)
        .onHover { hovering in
            if hovering {
                collapseTask?.cancel()
                if !state.isExpanded {
                    state.isExpanded = true
                    media.poll()
                    media.readVolume()
                }
            } else {
                scheduleCollapse()
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            shelf.add(urls)
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
            if targeted {
                collapseTask?.cancel()
                state.isExpanded = true
            }
        }
    }

    private func scheduleCollapse() {
        collapseTask?.cancel()
        let task = DispatchWorkItem {
            if !isDropTargeted && !state.isPinned {
                state.isExpanded = false
            }
        }
        collapseTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: task)
    }

    /// Gradient or user image behind the expanded card, darkened at the
    /// top so it blends into the physical notch and text stays readable.
    private var backgroundLayer: some View {
        Group {
            if case .preset(let name) = state.background {
                // Slow drift: gentle hue rotation + zoom so the gradient
                // feels alive without demanding attention (or battery —
                // it only exists while expanded).
                TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { context in
                    let time: Double = context.date.timeIntervalSinceReferenceDate
                    let hue: Double = sin(time / 7.0) * 10.0
                    let zoom: CGFloat = 1.08 + 0.05 * CGFloat(sin(time / 9.0))
                    NotchBackground.presetGradient(name)
                        .hueRotation(.degrees(hue))
                        .scaleEffect(zoom)
                }
            } else if let image = state.customBackgroundImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.black
            }
        }
        .overlay(
            LinearGradient(
                colors: [.black.opacity(0.85), .black.opacity(0.35)],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    // MARK: - Collapsed (resting) layout

    /// Left wing: artwork (music) or the activity's icon. Right wing:
    /// activity text, a live countdown, or the equalizer — the strip
    /// under the physical notch stays empty.
    private var collapsedActivity: some View {
        HStack {
            leftWingContent
                .frame(width: 18, height: 18)

            Spacer()

            rightWingContent
        }
        .padding(.horizontal, 8)
        .frame(width: islandSize.width, height: state.notchSize.height)
    }

    @ViewBuilder
    private var leftWingContent: some View {
        if media.nowPlaying?.isPlaying == true, let artwork = media.artwork {
            Image(nsImage: artwork)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else if let activity = activities.current {
            PulsingSymbol(symbol: activity.symbol, tint: activity.tint, pulses: activity.pulses)
        } else if timers.isRunning {
            Image(systemName: "timer")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
        } else {
            Image(systemName: "music.note")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    @ViewBuilder
    private var rightWingContent: some View {
        if let activity = activities.current {
            HStack(spacing: 4) {
                // If music artwork occupies the left wing, the icon
                // rides along with the text on the right.
                if media.nowPlaying?.isPlaying == true, media.artwork != nil {
                    PulsingSymbol(symbol: activity.symbol, tint: activity.tint, pulses: activity.pulses)
                }
                Text(activity.text)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
            }
        } else if timers.isRunning {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(timers.remainingString(at: context.date))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
            }
        } else if media.nowPlaying?.isPlaying == true {
            EqualizerBars()
        }
    }

    // MARK: - Expanded layout

    private var expandedContent: some View {
        VStack(spacing: 6) {
            // Leave the physical notch strip empty — content starts below it.
            Spacer().frame(height: state.notchSize.height)

            if let activity = activities.current {
                activityBanner(activity)
            }
            mediaRow
            volumeRow
            shelfRow
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private func activityBanner(_ activity: NotchActivity) -> some View {
        HStack(spacing: 6) {
            PulsingSymbol(symbol: activity.symbol, tint: activity.tint, pulses: activity.pulses)
            MarqueeBlock(resetKey: activity.detail) {
                Text(activity.detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
            }
        }
        .frame(height: 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mediaRow: some View {
        HStack(spacing: 10) {
            // Clicking artwork or the title opens the app that's playing.
            HStack(spacing: 10) {
                artworkView

                MarqueeBlock(
                    resetKey: "\(media.nowPlaying?.title ?? "")|\(media.nowPlaying?.artist ?? "")"
                ) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(media.nowPlaying?.title ?? "Nothing playing")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(media.nowPlaying?.artist ?? "Open Spotify or Music")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: 130, alignment: .leading)

                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .opacity(isSongHovered && media.nowPlaying != nil ? 1 : 0)
                    .animation(.easeOut(duration: 0.15), value: isSongHovered)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                media.openPlayerApp()
            }
            .onHover { hovering in
                isSongHovered = hovering
                guard media.nowPlaying != nil else { return }
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .help(media.nowPlaying == nil ? "" : "Open in \(media.nowPlaying!.source.rawValue)")

            if let playing = media.nowPlaying, playing.duration > 0 {
                progressScrubber(playing)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 6)
            } else {
                Spacer(minLength: 6)
            }

            HStack(spacing: 12) {
                transportButton("backward.fill", size: 12) { media.previousTrack() }
                transportButton(
                    media.nowPlaying?.isPlaying == true ? "pause.fill" : "play.fill",
                    size: 17
                ) { media.playPause() }
                transportButton("forward.fill", size: 12) { media.nextTrack() }
            }
            .opacity(media.nowPlaying == nil ? 0.3 : 1)
            .disabled(media.nowPlaying == nil)
        }
    }

    private var artworkView: some View {
        Group {
            if let artwork = media.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.white.opacity(0.08))
                    Image(systemName: media.nowPlaying?.source == .music ? "music.note" : "music.note.list")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
        }
        .frame(width: 38, height: 38)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func transportButton(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size + 10, height: size + 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Live progress bar between song info and transport controls.
    /// Extrapolates from the last poll so it glides instead of jumping,
    /// and is draggable to seek within the track.
    private func progressScrubber(_ playing: NowPlaying) -> some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let elapsed = playing.isPlaying
                ? context.date.timeIntervalSince(playing.fetchedAt)
                : 0
            let livePosition = min(playing.duration, max(0, playing.position + elapsed))

            Slider(
                value: Binding(
                    get: { isScrubbing ? scrubPosition : livePosition },
                    set: { scrubPosition = $0 }
                ),
                in: 0...max(playing.duration, 1)
            ) { editing in
                if editing {
                    isScrubbing = true
                    scrubPosition = livePosition
                } else {
                    isScrubbing = false
                    media.seek(to: scrubPosition)
                }
            }
            .controlSize(.mini)
            .tint(.white)
            .help("\(Self.timeString(livePosition)) / \(Self.timeString(playing.duration))")
        }
    }

    private static func timeString(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private var volumeRow: some View {
        HStack(spacing: 8) {
            Image(systemName: media.outputDevice.symbolName)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 16)
                .help(media.outputDevice.name)
            Slider(
                value: Binding(
                    get: { media.volume },
                    set: { media.setVolume($0) }
                ),
                in: 0...1
            )
            .controlSize(.small)
            .tint(.white)
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.5))

            timerControls
                .padding(.leading, 4)
        }
    }

    @ViewBuilder
    private var timerControls: some View {
        if timers.isRunning {
            HStack(spacing: 4) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(timers.remainingString(at: context.date))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                }
                Button {
                    timers.cancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .help("Cancel timer")
            }
        } else {
            Menu {
                ForEach([5, 10, 15, 25, 45, 60], id: \.self) { minutes in
                    Button("\(minutes) min") { timers.start(minutes: minutes) }
                }
            } label: {
                Image(systemName: "timer")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Start a timer")
        }
    }

    private var shelfRow: some View {
        Group {
            if shelf.items.isEmpty {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        .white.opacity(isDropTargeted ? 0.6 : 0.18),
                        style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                    )
                    .overlay {
                        Label("Drop files here to collect & share", systemImage: "tray.and.arrow.down")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.45))
                    }
            } else {
                HStack(spacing: 8) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(shelf.items, id: \.self) { url in
                                shelfItem(url)
                            }
                        }
                        .padding(.horizontal, 4)
                    }

                    Divider()
                        .frame(height: 24)
                        .overlay(.white.opacity(0.2))

                    ShareButton(
                        items: { shelf.items },
                        onPickerBegin: {
                            collapseTask?.cancel()
                            state.isPinned = true
                        },
                        onPickerEnd: {
                            state.isPinned = false
                            scheduleCollapse()
                        }
                    )
                    .frame(width: 24, height: 24)
                    .help("Share all files (AirDrop, WhatsApp, …)")

                    Button {
                        shelf.clear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .help("Clear shelf")
                }
            }
        }
        .frame(height: 40)
    }

    private func shelfItem(_ url: URL) -> some View {
        VStack(spacing: 1) {
            Image(nsImage: FileShelf.icon(for: url))
                .resizable()
                .frame(width: 24, height: 24)
            Text(url.lastPathComponent)
                .font(.system(size: 8.5))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .frame(maxWidth: 52)
        }
        .padding(3)
        .contentShape(Rectangle())
        .onDrag {
            NSItemProvider(contentsOf: url) ?? NSItemProvider()
        }
        .contextMenu {
            Button("Share…") {
                let anchor = NSApp.windows.first { $0 is NotchPanel }?.contentView
                FileSharing.share([url], from: anchor)
            }
            Button("Open") { NSWorkspace.shared.open(url) }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            Divider()
            Button("Remove") { shelf.remove(url) }
        }
    }
}

/// Activity icon that can softly pulse for urgent states (low battery,
/// finished timer). Clock-driven, so re-renders can't desync it.
struct PulsingSymbol: View {
    var symbol: String
    var tint: Color
    var pulses: Bool

    var body: some View {
        if pulses {
            TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
                let time: Double = context.date.timeIntervalSinceReferenceDate
                let level: Double = 0.6 + 0.4 * sin(time * 4.0)
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                    .opacity(level)
            }
        } else {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
        }
    }
}

/// Tiny animated "music is playing" bars for the collapsed state.
/// Clock-driven at 10 fps — repeatForever animations render at full
/// display refresh and burn CPU all day for a 15-pt widget.
struct EqualizerBars: View {
    private let maxHeights: [CGFloat] = [11, 15, 8]
    private let rates: [Double] = [3.25, 4.25, 2.6]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { context in
            let time: Double = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<3, id: \.self) { index in
                    bar(index: index, time: time)
                }
            }
            .frame(height: 15, alignment: .bottom)
        }
    }

    // Kept deliberately simple and explicitly typed: one big inline
    // expression here times out the type-checker on older Swift toolchains.
    private func bar(index: Int, time: Double) -> some View {
        let phase: Double = time * rates[index] + Double(index) * 1.7
        let wave: CGFloat = CGFloat((sin(phase) + 1.0) / 2.0)
        let height: CGFloat = 3.0 + (maxHeights[index] - 3.0) * wave
        return RoundedRectangle(cornerRadius: 1)
            .fill(.white.opacity(0.85))
            .frame(width: 2.5, height: height)
    }
}
