import AppKit
import SwiftUI

/// Native share button: opens NSSharingServicePicker (AirDrop, Messages,
/// Mail, WhatsApp, …) with the given file URLs. SwiftUI's ShareLink is
/// flaky with multiple file URLs, so we drive AppKit directly.
struct ShareButton: NSViewRepresentable {
    var items: () -> [URL]
    /// Called when the picker opens/closes so the island can pin itself
    /// open — otherwise hover-away collapses it and kills the popover.
    var onPickerBegin: () -> Void = {}
    var onPickerEnd: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(items: items, onBegin: onPickerBegin, onEnd: onPickerEnd)
    }

    func makeNSView(context: Context) -> NSButton {
        let image = NSImage(
            systemSymbolName: "square.and.arrow.up",
            accessibilityDescription: "Share"
        )!.withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))!
        let button = NSButton(
            image: image,
            target: context.coordinator,
            action: #selector(Coordinator.share(_:))
        )
        button.isBordered = false
        button.contentTintColor = .white
        button.toolTip = "Share all files"
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.items = items
        context.coordinator.onBegin = onPickerBegin
        context.coordinator.onEnd = onPickerEnd
    }

    final class Coordinator: NSObject, NSSharingServicePickerDelegate {
        var items: () -> [URL]
        var onBegin: () -> Void
        var onEnd: () -> Void
        private var activePicker: NSSharingServicePicker?

        init(items: @escaping () -> [URL],
             onBegin: @escaping () -> Void,
             onEnd: @escaping () -> Void) {
            self.items = items
            self.onBegin = onBegin
            self.onEnd = onEnd
        }

        @objc func share(_ sender: NSButton) {
            let urls = items()
            guard !urls.isEmpty else { return }
            onBegin()
            // The panel is non-activating; share UIs (AirDrop window etc.)
            // need the app active to present properly.
            NSApp.activate(ignoringOtherApps: true)
            let picker = NSSharingServicePicker(items: urls)
            picker.delegate = self
            activePicker = picker
            picker.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }

        // Fires both when a service is chosen and when the picker is
        // dismissed without a choice (service == nil).
        func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker,
                                  didChoose service: NSSharingService?) {
            activePicker = nil
            onEnd()
        }
    }
}

enum FileSharing {
    /// Share a single file from a context menu (no anchor view available,
    /// so anchor to the key/panel window's content view).
    static func share(_ urls: [URL], from view: NSView?) {
        guard !urls.isEmpty, let view else { return }
        NSApp.activate(ignoringOtherApps: true)
        let picker = NSSharingServicePicker(items: urls)
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }
}
