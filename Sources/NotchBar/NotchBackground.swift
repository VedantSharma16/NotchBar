import AppKit
import SwiftUI

/// Background of the expanded island: plain black, a built-in abstract
/// gradient, or the user's own image. The collapsed notch always stays
/// pure black so it blends into the physical notch.
enum NotchBackground: Equatable {
    case plain
    case preset(String)
    case custom(URL)

    static let presetNames = ["Aurora", "Sunset", "Ocean", "Nebula", "Graphite"]

    static let defaultsKey = "notchBackground"

    // MARK: - Persistence

    var storageString: String {
        switch self {
        case .plain: return "plain"
        case .preset(let name): return "preset:\(name)"
        case .custom(let url): return "custom:\(url.path)"
        }
    }

    init(storageString: String?) {
        guard let raw = storageString else {
            self = .plain
            return
        }
        if raw.hasPrefix("preset:") {
            let name = String(raw.dropFirst("preset:".count))
            self = Self.presetNames.contains(name) ? .preset(name) : .plain
        } else if raw.hasPrefix("custom:") {
            let path = String(raw.dropFirst("custom:".count))
            self = FileManager.default.fileExists(atPath: path)
                ? .custom(URL(fileURLWithPath: path))
                : .plain
        } else {
            self = .plain
        }
    }

    // MARK: - Rendering

    @ViewBuilder
    static func presetGradient(_ name: String) -> some View {
        switch name {
        case "Aurora":
            LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.18, blue: 0.16),
                    Color(red: 0.05, green: 0.42, blue: 0.38),
                    Color(red: 0.25, green: 0.12, blue: 0.45),
                ],
                startPoint: .bottomLeading, endPoint: .topTrailing
            )
        case "Sunset":
            LinearGradient(
                colors: [
                    Color(red: 0.45, green: 0.08, blue: 0.25),
                    Color(red: 0.75, green: 0.25, blue: 0.15),
                    Color(red: 0.95, green: 0.55, blue: 0.25),
                ],
                startPoint: .bottom, endPoint: .topTrailing
            )
        case "Ocean":
            RadialGradient(
                colors: [
                    Color(red: 0.05, green: 0.35, blue: 0.55),
                    Color(red: 0.02, green: 0.12, blue: 0.3),
                    Color(red: 0.0, green: 0.04, blue: 0.12),
                ],
                center: .topLeading, startRadius: 20, endRadius: 420
            )
        case "Nebula":
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.12, green: 0.02, blue: 0.25),
                        Color(red: 0.3, green: 0.05, blue: 0.4),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                RadialGradient(
                    colors: [Color(red: 0.9, green: 0.3, blue: 0.6).opacity(0.5), .clear],
                    center: .bottomTrailing, startRadius: 10, endRadius: 300
                )
            }
        case "Graphite":
            LinearGradient(
                colors: [
                    Color(white: 0.22),
                    Color(white: 0.1),
                    Color(white: 0.04),
                ],
                startPoint: .top, endPoint: .bottom
            )
        default:
            Color.black
        }
    }
}
