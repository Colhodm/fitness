import ActivityKit
import AppIntents
import Foundation

enum RestSync {
    static let endsAtKey = "rest.endsAt"
    static let startedAtKey = "rest.startedAt"
    static let changed = Notification.Name("RestSync.changed")

    static func write(endsAt: Date?, startedAt: Date?) {
        let d = AppGroup.defaults
        if let endsAt { d.set(endsAt.timeIntervalSince1970, forKey: endsAtKey) } else { d.removeObject(forKey: endsAtKey) }
        if let startedAt { d.set(startedAt.timeIntervalSince1970, forKey: startedAtKey) } else { d.removeObject(forKey: startedAtKey) }
    }

    static func read() -> (endsAt: Date?, startedAt: Date?) {
        let d = AppGroup.defaults
        let e = d.double(forKey: endsAtKey)
        let s = d.double(forKey: startedAtKey)
        return (e > 0 ? Date(timeIntervalSince1970: e) : nil, s > 0 ? Date(timeIntervalSince1970: s) : nil)
    }

    static func apply(_ change: (inout RestActivityAttributes.ContentState) -> Void) async {
        for activity in Activity<RestActivityAttributes>.activities {
            var state = activity.content.state
            change(&state)
            RestSync.write(endsAt: state.restEndsAt, startedAt: state.restStartedAt)
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
        await MainActor.run { NotificationCenter.default.post(name: RestSync.changed, object: nil) }
    }
}

struct AddRestTimeIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Add 15 seconds of rest"
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        await RestSync.apply { state in
            if let end = state.restEndsAt, end > Date() {
                state.restEndsAt = end.addingTimeInterval(15)
            }
        }
        return .result()
    }
}

struct SkipRestIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Skip rest"
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        await RestSync.apply { state in
            state.restEndsAt = nil
            state.restStartedAt = nil
        }
        return .result()
    }
}
