import Foundation
import SwiftData
import WidgetKit

/// Writes the App Group snapshot widgets read, then asks WidgetKit to reload.
@MainActor
final class WidgetSync {
    static let shared = WidgetSync()
    var context: ModelContext?

    func refresh() {
        guard let context else { return }
        let settings = AppSettings.shared
        let health = HealthStore.shared
        let workouts = (try? context.fetch(FetchDescriptor<Workout>())) ?? []
        let routines = (try? context.fetch(FetchDescriptor<Routine>())) ?? []
        var snap = WidgetSnapshot()
        snap.unit = settings.unit.rawValue
        let trend = BodyMath.trend(health.weights)
        if let last = trend.last {
            snap.trendWeight = Units.display(last.trend)
            snap.trendDelta30 = BodyMath.change(trend, days: 30).map { Units.display($0) }
            let since = Date().addingTimeInterval(-30 * 86400)
            snap.trendSparkline = trend.filter { $0.date >= since }.map { Units.display($0.trend) }
        }
        if let next = Analytics.nextRoutine(routines, workouts: workouts) {
            snap.nextRoutineName = next.name.lowercased().hasSuffix("day") ? next.name : "\(next.name) Day"
            snap.nextRoutineExercises = next.items.count
            snap.nextRoutineID = next.uuid.uuidString
        }
        let start = Analytics.weekStart()
        snap.weekLabel = Fmt.weekRange(start)
        snap.liftingDone = Analytics.workouts(workouts, inWeekOf: Date()).count
        snap.liftingGoal = settings.weeklyLiftGoal
        let weekRuns = health.runs.filter { $0.start >= start }
        snap.runDistance = Units.runDisplay(weekRuns.reduce(0) { $0 + $1.meters })
        snap.runGoal = settings.unit == .lb ? settings.weeklyRunGoal : settings.weeklyRunGoal * 1.609
        snap.distanceUnit = Units.runLabel
        snap.updatedAt = Date()
        if snap != WidgetSnapshot.load() {
            snap.save()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
