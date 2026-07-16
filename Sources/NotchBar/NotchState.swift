import AppKit
import SwiftUI

/// Geometry + expansion state shared between the panel (AppKit) and the SwiftUI view.
final class NotchState: ObservableObject {
    @Published var isExpanded = false

    /// While true (e.g. the share picker is open), hover-away must not
    /// collapse the island — collapsing would tear down the picker popover.
    @Published var isPinned = false

    /// Background of the expanded card (collapsed notch stays black).
    @Published var background: NotchBackground {
        didSet {
            UserDefaults.standard.set(background.storageString, forKey: NotchBackground.defaultsKey)
            loadCustomBackgroundImage()
        }
    }

    /// Cached image for `.custom` so we don't hit the disk on every render.
    @Published var customBackgroundImage: NSImage?

    init() {
        background = NotchBackground(
            storageString: UserDefaults.standard.string(forKey: NotchBackground.defaultsKey)
        )
        loadCustomBackgroundImage()
    }

    private func loadCustomBackgroundImage() {
        if case .custom(let url) = background {
            customBackgroundImage = NSImage(contentsOf: url)
        } else {
            customBackgroundImage = nil
        }
    }

    /// True while there's something to show at rest (music, an activity,
    /// a running timer) — the collapsed island grows small "wings".
    @Published var hasActivity = false

    /// Right wing widens when it's showing text (activity / countdown)
    /// instead of the equalizer bars.
    @Published var rightWingWidth: CGFloat = 32

    /// Expanded card grows a slim banner row while an activity is live.
    @Published var showsActivityBanner = false

    /// Cursor is approaching the collapsed notch — breathe slightly wider.
    @Published var isNear = false

    /// Size of the physical notch (or a fake island on notch-less displays).
    @Published var notchSize = CGSize(width: 200, height: 32)

    /// Width of the left (artwork/icon) wing.
    let leftWingWidth: CGFloat = 32

    var collapsedSize: CGSize {
        let breathe: CGFloat = (!isExpanded && isNear) ? 12 : 0
        guard hasActivity else {
            return CGSize(width: notchSize.width + breathe, height: notchSize.height)
        }
        return CGSize(
            width: notchSize.width + leftWingWidth + rightWingWidth + breathe,
            height: notchSize.height
        )
    }

    /// Full size of the expanded island, including the notch strip at the top.
    var expandedSize: CGSize {
        CGSize(width: 400, height: 158 + (showsActivityBanner ? 22 : 0))
    }

    /// Largest the island can ever get — the window is sized for this.
    private let maxExpandedSize = CGSize(width: 400, height: 180)

    /// Extra transparent padding around the content so shadows aren't clipped.
    private let windowPadding: CGFloat = 24

    var windowSize: CGSize {
        CGSize(width: maxExpandedSize.width + windowPadding * 2,
               height: maxExpandedSize.height + windowPadding)
    }

    func updateMetrics(for screen: NSScreen) {
        let topInset = screen.safeAreaInsets.top
        if topInset > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            // Real notch: exact width is what's left between the two menu bar areas.
            let width = screen.frame.width - left.width - right.width
            notchSize = CGSize(width: width, height: topInset)
        } else {
            // No notch (external display / older Mac): draw a small fake island.
            notchSize = CGSize(width: 220, height: 30)
        }
    }

    /// The clickable region in the window's AppKit coordinate space (y-up),
    /// used by the hosting view to pass through clicks everywhere else.
    func interactiveRect(inWindowOfSize windowSize: CGSize) -> CGRect {
        let size = isExpanded ? expandedSize : collapsedSize
        // Small margin so the hover zone is slightly forgiving.
        let margin: CGFloat = isExpanded ? 0 : 4
        return CGRect(
            x: (windowSize.width - size.width) / 2 - margin,
            y: windowSize.height - size.height - margin,
            width: size.width + margin * 2,
            height: size.height + margin
        )
    }
}
