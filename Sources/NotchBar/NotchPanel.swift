import AppKit
import SwiftUI

/// Borderless, non-activating panel that floats above the menu bar,
/// on every space, and never steals focus from the frontmost app.
final class NotchPanel: NSPanel {
    init(
        state: NotchState,
        media: MediaController,
        shelf: FileShelf,
        activities: ActivityCenter,
        timers: NotchTimerManager
    ) {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true

        let root = NotchView(
            state: state, media: media, shelf: shelf,
            activities: activities, timers: timers
        )
        let hosting = PassThroughHostingView(rootView: root)
        hosting.interactiveRegion = { [weak state, weak self] in
            guard let state, let self else { return .zero }
            return state.interactiveRect(inWindowOfSize: self.frame.size)
        }
        contentView = hosting
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Hosting view that only accepts mouse events inside the island itself,
/// so clicks in the transparent parts of the window reach whatever is below.
final class PassThroughHostingView: NSHostingView<NotchView> {
    var interactiveRegion: (() -> CGRect)?

    required init(rootView: NotchView) {
        super.init(rootView: rootView)
    }

    @MainActor required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if let region = interactiveRegion?(), !region.contains(local) {
            return nil
        }
        return super.hitTest(point)
    }
}
