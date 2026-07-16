import AppKit
import Foundation

/// A temporary holding area for files: drag anything onto the expanded
/// island, drag it back out into Finder, Mail, Slack, wherever.
final class FileShelf: ObservableObject {
    @Published var items: [URL] = []

    private static let defaultsKey = "shelfItems"

    init() {
        restore()
    }

    func add(_ urls: [URL]) {
        for url in urls where !items.contains(url) {
            items.append(url)
        }
        persist()
    }

    func remove(_ url: URL) {
        items.removeAll { $0 == url }
        persist()
    }

    func clear() {
        items.removeAll()
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(items.map(\.path), forKey: Self.defaultsKey)
    }

    private func restore() {
        guard let paths = UserDefaults.standard.stringArray(forKey: Self.defaultsKey) else { return }
        items = paths
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    static func icon(for url: URL) -> NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }
}
