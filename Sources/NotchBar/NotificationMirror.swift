import AppKit
import SQLite3
import SwiftUI

/// Opt-in delivery/ride tracking: reads the macOS notification store
/// (requires Full Disk Access), keeps only notifications matching
/// activity keywords, and surfaces them as transient notch activities.
///
/// Privacy contract: the app is fully functional without FDA — this
/// feature simply stays dormant. All parsing happens on-device; nothing
/// is stored beyond the last-seen row id, and nothing ever leaves the Mac.
final class NotificationMirror: ObservableObject {
    private static let enabledKey = "notificationMirrorEnabled"
    private static let lastRecKey = "notificationMirrorLastRec"

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            isEnabled ? startPolling() : stopPolling()
        }
    }

    private let activities: ActivityCenter
    private var timer: Timer?
    private var lastRecID: Int64 {
        get { Int64(UserDefaults.standard.integer(forKey: Self.lastRecKey)) }
        set { UserDefaults.standard.set(Int(newValue), forKey: Self.lastRecKey) }
    }

    private let dbPath = NSHomeDirectory()
        + "/Library/Group Containers/group.com.apple.usernotificationcenter/db2/db"

    /// Keyword → SF symbol for the notch. First match wins.
    private static let categories: [(keywords: [String], symbol: String)] = [
        (["driver", "ride", "cab", "pickup", "arriving"], "car.fill"),
        (["order", "food", "restaurant", "prepared", "cooking"], "takeoutbag.and.cup.and.straw.fill"),
        (["package", "parcel", "shipped", "courier", "dispatched", "out for delivery", "delivered", "delivery"], "shippingbox.fill"),
        (["flight", "boarding", "gate", "departure", "departs", "landed"], "airplane"),
        (["on the way", "on its way", "tracking"], "location.fill"),
    ]

    init(activities: ActivityCenter) {
        self.activities = activities
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        if isEnabled { startPolling() }
    }

    var hasFullDiskAccess: Bool {
        FileManager.default.isReadableFile(atPath: dbPath)
    }

    // MARK: - Polling

    private func startPolling() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    /// Cheap no-op until FDA is granted — this is also the "detect when
    /// permission arrives and light up automatically" mechanism.
    private func poll() {
        guard hasFullDiskAccess else { return }

        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return
        }
        defer { sqlite3_close(db) }

        // First successful read: baseline to the newest row so we don't
        // replay the user's notification history onto the notch.
        if lastRecID == 0 {
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, "SELECT MAX(rec_id) FROM record", -1, &statement, nil) == SQLITE_OK,
               sqlite3_step(statement) == SQLITE_ROW {
                lastRecID = max(1, sqlite3_column_int64(statement, 0))
            }
            sqlite3_finalize(statement)
            return
        }

        var statement: OpaquePointer?
        let query = "SELECT rec_id, data FROM record WHERE rec_id > ? ORDER BY rec_id ASC LIMIT 50"
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, lastRecID)

        while sqlite3_step(statement) == SQLITE_ROW {
            let recID = sqlite3_column_int64(statement, 0)
            lastRecID = max(lastRecID, recID)
            guard let blob = sqlite3_column_blob(statement, 1) else { continue }
            let size = Int(sqlite3_column_bytes(statement, 1))
            let data = Data(bytes: blob, count: size)
            handleRecord(data)
        }
    }

    private func handleRecord(_ data: Data) {
        guard let plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any],
              let request = plist["req"] as? [String: Any]
        else { return }

        let title = request["titl"] as? String ?? ""
        let subtitle = request["subt"] as? String ?? ""
        let body = request["body"] as? String ?? ""
        let haystack = "\(title) \(subtitle) \(body)".lowercased()

        guard let symbol = Self.categories.first(where: { category in
            category.keywords.contains { haystack.contains($0) }
        })?.symbol else { return }

        let headline = title.isEmpty ? body : title
        let detail = [title, subtitle, body]
            .filter { !$0.isEmpty }
            .joined(separator: " — ")

        DispatchQueue.main.async { [weak self] in
            self?.activities.post(NotchActivity(
                key: "mirror",
                symbol: symbol,
                tint: .cyan,
                text: String(headline.prefix(12)),
                detail: detail,
                priority: 85,
                expiresAt: Date().addingTimeInterval(60)
            ))
        }
    }

    // MARK: - Enablement UI helpers

    static func openFullDiskAccessSettings() {
        let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }
}
