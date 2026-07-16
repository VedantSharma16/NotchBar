import SwiftUI

/// One thing the notch can be "about" right now: a charge event, a mic
/// indicator, a finished timer, a delivery update.
struct NotchActivity: Identifiable, Equatable {
    /// Stable key so repeat posts replace instead of stacking
    /// (e.g. battery updates reuse "power").
    let key: String
    var symbol: String
    var tint: Color
    /// Short text for the collapsed wing ("84%", "Arriving").
    var text: String
    /// Longer line for the expanded banner.
    var detail: String
    /// Higher wins when several activities are alive.
    var priority: Int
    var expiresAt: Date?
    var pulses: Bool = false

    var id: String { key }

    var isAlive: Bool {
        guard let expiresAt else { return true }
        return expiresAt > Date()
    }
}

/// Single arbiter for what the collapsed notch shows. Features post
/// activities; the highest-priority live one (ties → most recent) wins.
final class ActivityCenter: ObservableObject {
    @Published private(set) var activities: [NotchActivity] = []
    private var purgeTimer: Timer?

    var current: NotchActivity? {
        let alive = activities.filter(\.isAlive)
        guard !alive.isEmpty else { return nil }
        let top = alive.map(\.priority).max()!
        // Array order is insertion order, so last match is the most recent.
        return alive.last { $0.priority == top }
    }

    func post(_ activity: NotchActivity) {
        activities.removeAll { $0.key == activity.key }
        activities.append(activity)
        schedulePurgeIfNeeded()
    }

    func remove(key: String) {
        activities.removeAll { $0.key == key }
    }

    /// While anything can expire, tick once a second to drop dead
    /// activities (and stop again once the list is static).
    private func schedulePurgeIfNeeded() {
        guard purgeTimer == nil, activities.contains(where: { $0.expiresAt != nil }) else { return }
        purgeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.activities.contains(where: { !$0.isAlive }) {
                self.activities.removeAll { !$0.isAlive }
            }
            if !self.activities.contains(where: { $0.expiresAt != nil }) {
                self.purgeTimer?.invalidate()
                self.purgeTimer = nil
            }
        }
    }
}
