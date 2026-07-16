import Foundation
import ServiceManagement

/// Registers the app as a login item. Enabled by default; the status bar
/// menu exposes a toggle that persists across launches.
enum LaunchAtLogin {
    private static let prefKey = "launchAtLogin"

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: prefKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: prefKey)
            apply(newValue)
        }
    }

    /// Call at startup so the system registration matches the saved preference.
    static func syncAtStartup() {
        apply(isEnabled)
    }

    private static func apply(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            NSLog("LaunchAtLogin: applied enabled=%d status=%d",
                  enabled, SMAppService.mainApp.status.rawValue)
        } catch {
            NSLog("LaunchAtLogin: failed to apply enabled=%d: %@",
                  enabled, error.localizedDescription)
        }
    }
}
