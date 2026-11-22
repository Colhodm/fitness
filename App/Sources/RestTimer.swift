import ActivityKit
import Foundation
import UIKit
import UserNotifications

@MainActor
final class RestTimer: ObservableObject {
    static let shared = RestTimer()

    @Published private(set) var endsAt: Date?
    @Published private(set) var startedAt: Date?
    @Published private(set) var now = Date()
    var onChange: (() -> Void)?

    private var ticker: Timer?
    private var warned = false

    init() {
        NotificationCenter.default.addObserver(forName: RestSync.changed, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.syncFromShared() }
        }
    }

    var isRunning: Bool { (endsAt ?? .distantPast) > now }
    var remaining: TimeInterval { max(0, (endsAt ?? now).timeIntervalSince(now)) }
    var total: TimeInterval { max(1, (endsAt ?? now).timeIntervalSince(startedAt ?? now)) }
    var progress: Double { isRunning ? remaining / total : 0 }

    func start(seconds: Int) {
        guard seconds > 0 else { return }
        startedAt = Date()
        endsAt = Date().addingTimeInterval(TimeInterval(seconds))
        warned = false
        changed()
    }

    func add(_ seconds: TimeInterval) {
        guard let e = endsAt, isRunning else { return }
        let newEnd = e.addingTimeInterval(seconds)
        if newEnd <= Date() { skip(); return }
        endsAt = newEnd
        if remaining > 10 { warned = false }
        changed()
    }

    func skip() {
        endsAt = nil
        startedAt = nil
        changed()
    }

    /// Picks up +15 s / Skip taps made on the Lock Screen or Dynamic Island.
    func syncFromShared() {
        let shared = RestSync.read()
        if shared.endsAt != endsAt {
            endsAt = shared.endsAt
            startedAt = shared.startedAt ?? startedAt
            now = Date()
            scheduleNotification()
            ensureTicker()
        }
    }

    private func changed() {
        now = Date()
        RestSync.write(endsAt: endsAt, startedAt: startedAt)
        scheduleNotification()
        ensureTicker()
        onChange?()
    }

    private func ensureTicker() {
        if isRunning, ticker == nil {
            ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        }
    }

    private func tick() {
        now = Date()
        guard let endsAt else { stopTicker(); return }
        let left = endsAt.timeIntervalSince(now)
        if left <= 10, left > 0, !warned {
            warned = true
            if AppSettings.shared.hapticBeforeEnd { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
        }
        if left <= 0 {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            self.endsAt = nil
            self.startedAt = nil
            RestSync.write(endsAt: nil, startedAt: nil)
            stopTicker()
            onChange?()
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func scheduleNotification() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["rest"])
        guard let endsAt, endsAt > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Rest's up"
        content.body = "Time for your next set."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, endsAt.timeIntervalSinceNow), repeats: false)
        center.add(UNNotificationRequest(identifier: "rest", content: content, trigger: trigger))
    }
}

/// Owns the single workout Live Activity (Lock Screen + Dynamic Island).
@MainActor
final class LiveActivityController {
    static let shared = LiveActivityController()
    private var activity: Activity<RestActivityAttributes>?

    func start(workoutName: String, startedAt: Date, state: RestActivityAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if let existing = Activity<RestActivityAttributes>.activities.first(where: { $0.attributes.workoutStartedAt == startedAt }) {
            activity = existing
            update(state)
            return
        }
        endAll()
        do {
            activity = try Activity.request(
                attributes: RestActivityAttributes(workoutName: workoutName, workoutStartedAt: startedAt),
                content: ActivityContent(state: state, staleDate: state.restEndsAt))
        } catch {
            print("Live Activity failed: \(error)")
        }
    }

    func update(_ state: RestActivityAttributes.ContentState) {
        guard let activity else { return }
        // staleDate = rest end, so the system re-renders as "Go" even if the app is suspended when rest runs out.
        Task { await activity.update(ActivityContent(state: state, staleDate: state.restEndsAt)) }
    }

    func endAll() {
        let all = Activity<RestActivityAttributes>.activities
        activity = nil
        Task {
            for a in all { await a.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
