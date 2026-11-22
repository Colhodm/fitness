import Foundation

/// Small, precomputed summary the app writes to the App Group so widgets never touch SwiftData or HealthKit.
struct WidgetSnapshot: Codable, Equatable {
    var unit: String = "lb"
    var trendWeight: Double?
    var trendDelta30: Double?
    var trendSparkline: [Double] = []
    var nextRoutineName: String?
    var nextRoutineExercises: Int = 0
    var nextRoutineID: String?
    var weekLabel: String = ""
    var liftingDone: Int = 0
    var liftingGoal: Int = 4
    var runDistance: Double = 0
    var runGoal: Double = 15
    var distanceUnit: String = "mi"
    var updatedAt: Date = .distantPast

    static let key = "widgetSnapshot.v1"

    static func load() -> WidgetSnapshot? {
        guard let data = AppGroup.defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            AppGroup.defaults.set(data, forKey: Self.key)
        }
    }
}
