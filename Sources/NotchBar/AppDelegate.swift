import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NotchPanel?
    private var statusItem: NSStatusItem?
    private let state = NotchState()
    private let media = MediaController()
    private let shelf = FileShelf()
    private let activities = ActivityCenter()
    private var timers: NotchTimerManager!
    private var systemEvents: SystemEventsMonitor!
    private var mirror: NotificationMirror!
    private var cancellables = Set<AnyCancellable>()
    private var backgroundMenu: NSMenu?
    private var proximityTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        timers = NotchTimerManager(activities: activities)
        systemEvents = SystemEventsMonitor(activities: activities)
        mirror = NotificationMirror(activities: activities)

        setupStatusItem()
        setupPanel()
        media.start()
        systemEvents.start()
        startProximityWatch()
        LaunchAtLogin.syncAtStartup()

        // One place decides what the collapsed notch is "about".
        Publishers.CombineLatest3(media.$nowPlaying, activities.$activities, timers.$endDate)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] playing, _, timerEnd in
                guard let self else { return }
                let activity = self.activities.current
                let timerRunning = timerEnd != nil
                self.state.hasActivity =
                    (playing?.isPlaying == true) || activity != nil || timerRunning
                self.state.rightWingWidth = (activity != nil || timerRunning) ? 58 : 32
                self.state.showsActivityBanner = activity != nil
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func screensChanged() {
        positionPanel()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "sparkle",
            accessibilityDescription: "NotchBar"
        )
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "NotchBar", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())

        let backgroundItem = NSMenuItem(title: "Background", action: nil, keyEquivalent: "")
        let bgMenu = NSMenu(title: "Background")

        let plainItem = NSMenuItem(
            title: "Plain Black",
            action: #selector(selectBackground(_:)),
            keyEquivalent: ""
        )
        plainItem.target = self
        plainItem.representedObject = "plain"
        bgMenu.addItem(plainItem)

        bgMenu.addItem(.separator())
        for name in NotchBackground.presetNames {
            let presetItem = NSMenuItem(
                title: name,
                action: #selector(selectBackground(_:)),
                keyEquivalent: ""
            )
            presetItem.target = self
            presetItem.representedObject = "preset:\(name)"
            bgMenu.addItem(presetItem)
        }

        bgMenu.addItem(.separator())
        let customItem = NSMenuItem(
            title: "Choose Image…",
            action: #selector(chooseBackgroundImage),
            keyEquivalent: ""
        )
        customItem.target = self
        bgMenu.addItem(customItem)

        menu.addItem(backgroundItem)
        menu.setSubmenu(bgMenu, for: backgroundItem)
        backgroundMenu = bgMenu
        refreshBackgroundMenuChecks()

        let mirrorItem = NSMenuItem(
            title: "Delivery Tracking (Beta)",
            action: #selector(toggleMirror(_:)),
            keyEquivalent: ""
        )
        mirrorItem.target = self
        mirrorItem.state = mirror.isEnabled ? .on : .off
        menu.addItem(mirrorItem)

        let loginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin(_:)),
            keyEquivalent: ""
        )
        loginItem.target = self
        loginItem.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit NotchBar", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    @objc private func selectBackground(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        state.background = NotchBackground(storageString: raw)
        refreshBackgroundMenuChecks()
    }

    @objc private func chooseBackgroundImage() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "Choose a Notch Background"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            self.state.background = .custom(url)
            self.refreshBackgroundMenuChecks()
        }
    }

    private func refreshBackgroundMenuChecks() {
        guard let bgMenu = backgroundMenu else { return }
        let current = state.background
        for item in bgMenu.items {
            guard let raw = item.representedObject as? String else {
                // "Choose Image…" — checked when a custom image is active.
                if item.action == #selector(chooseBackgroundImage) {
                    if case .custom = current {
                        item.state = .on
                    } else {
                        item.state = .off
                    }
                }
                continue
            }
            item.state = NotchBackground(storageString: raw) == current ? .on : .off
        }
    }

    @objc private func toggleMirror(_ sender: NSMenuItem) {
        if mirror.isEnabled {
            mirror.isEnabled = false
        } else {
            mirror.isEnabled = true
            if !mirror.hasFullDiskAccess {
                showFullDiskAccessExplainer()
            }
        }
        sender.state = mirror.isEnabled ? .on : .off
    }

    private func showFullDiskAccessExplainer() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Delivery Tracking needs Full Disk Access"
        alert.informativeText = """
        To spot delivery and ride updates, NotchBar reads the macOS \
        notification store — that file is only accessible with Full Disk \
        Access.

        Everything is processed on this Mac: only notifications matching \
        delivery/ride keywords are shown, nothing is stored, and nothing \
        is ever uploaded or shared.

        NotchBar works normally without this — tracking just stays off. \
        Once you add NotchBar in System Settings, the feature turns on \
        automatically.
        """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            NotificationMirror.openFullDiskAccessSettings()
        }
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        LaunchAtLogin.isEnabled.toggle()
        sender.state = LaunchAtLogin.isEnabled ? .on : .off
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func setupPanel() {
        let panel = NotchPanel(
            state: state, media: media, shelf: shelf,
            activities: activities, timers: timers
        )
        self.panel = panel
        positionPanel()
        panel.orderFrontRegardless()
    }

    /// Cursor-proximity check (8 Hz, collapsed only): the notch breathes
    /// slightly wider as the pointer approaches.
    private func startProximityWatch() {
        proximityTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            guard let self, let panel = self.panel, !self.state.isExpanded else { return }
            let island = self.state.interactiveRect(inWindowOfSize: panel.frame.size)
                .offsetBy(dx: panel.frame.origin.x, dy: panel.frame.origin.y)
            let near = island.insetBy(dx: -80, dy: -50).contains(NSEvent.mouseLocation)
            if near != self.state.isNear {
                self.state.isNear = near
            }
        }
    }

    private func positionPanel() {
        guard let panel else { return }
        // Prefer the built-in display with a notch; fall back to the main screen.
        let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }

        state.updateMetrics(for: screen)

        let size = state.windowSize
        let frame = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        panel.setFrame(frame, display: true)
    }
}
