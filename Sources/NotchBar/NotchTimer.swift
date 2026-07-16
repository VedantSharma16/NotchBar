import SwiftUI

/// Simple countdown timer started from the expanded card; the collapsed
/// wing shows the remaining time ticking live. Posts a pulsing activity
/// when it finishes.
final class NotchTimerManager: ObservableObject {
    @Published var endDate: Date?

    private let activities: ActivityCenter
    private var completionTimer: Timer?

    init(activities: ActivityCenter) {
        self.activities = activities
    }

    var isRunning: Bool { endDate != nil }

    func start(minutes: Int) {
        activities.remove(key: "timer-done")
        let end = Date().addingTimeInterval(TimeInterval(minutes * 60))
        endDate = end
        completionTimer?.invalidate()
        completionTimer = Timer.scheduledTimer(
            withTimeInterval: end.timeIntervalSinceNow, repeats: false
        ) { [weak self] _ in
            self?.finish()
        }
    }

    func cancel() {
        completionTimer?.invalidate()
        completionTimer = nil
        endDate = nil
    }

    private func finish() {
        endDate = nil
        completionTimer = nil
        activities.post(NotchActivity(
            key: "timer-done",
            symbol: "bell.fill",
            tint: .yellow,
            text: "Done!",
            detail: "Timer finished",
            priority: 95,
            expiresAt: Date().addingTimeInterval(45),
            pulses: true
        ))
    }

    func remainingString(at date: Date) -> String {
        guard let endDate else { return "" }
        let remaining = max(0, Int(endDate.timeIntervalSince(date).rounded()))
        return String(format: "%d:%02d", remaining / 60, remaining % 60)
    }
}
