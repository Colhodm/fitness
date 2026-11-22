import ActivityKit
import Foundation

struct RestActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// When the current rest ends. `nil` while lifting (no rest running).
        var restEndsAt: Date?
        var restStartedAt: Date?
        var exerciseName: String
        /// e.g. "set 3 of 3"
        var upNext: String
        /// e.g. "160 × 9"
        var target: String

        var isResting: Bool {
            guard let restEndsAt else { return false }
            return restEndsAt > Date()
        }
    }

    var workoutName: String
    var workoutStartedAt: Date
}
