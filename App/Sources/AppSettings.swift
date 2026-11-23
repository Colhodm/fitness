import Foundation
import SwiftUI

enum WeightUnit: String, CaseIterable, Identifiable {
    case lb, kg
    var id: String { rawValue }
}

/// User preferences, persisted in the shared App Group defaults.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d = AppGroup.defaults

    @Published var unit: WeightUnit { didSet { d.set(unit.rawValue, forKey: "unit") } }
    @Published var barWeightLb: Double { didSet { d.set(barWeightLb, forKey: "barWeightLb") } }
    @Published var barWeightKg: Double { didSet { d.set(barWeightKg, forKey: "barWeightKg") } }
    /// Plate sizes (in the given unit) the user has at their gym.
    @Published var platesLb: [Double] { didSet { d.set(platesLb, forKey: "platesLb") } }
    @Published var platesKg: [Double] { didSet { d.set(platesKg, forKey: "platesKg") } }
    @Published var dumbbellMin: Double { didSet { d.set(dumbbellMin, forKey: "dbMin") } }
    @Published var dumbbellMax: Double { didSet { d.set(dumbbellMax, forKey: "dbMax") } }
    @Published var dumbbellStep: Double { didSet { d.set(dumbbellStep, forKey: "dbStep") } }
    @Published var defaultRest: Int { didSet { d.set(defaultRest, forKey: "defaultRest") } }
    @Published var autoStartRest: Bool { didSet { d.set(autoStartRest, forKey: "autoStartRest") } }
    @Published var hapticBeforeEnd: Bool { didSet { d.set(hapticBeforeEnd, forKey: "hapticBeforeEnd") } }
    /// Stored in pounds.
    @Published var upperIncrement: Double { didSet { d.set(upperIncrement, forKey: "upperIncrement") } }
    @Published var lowerIncrement: Double { didSet { d.set(lowerIncrement, forKey: "lowerIncrement") } }
    @Published var weeklyLiftGoal: Int { didSet { d.set(weeklyLiftGoal, forKey: "weeklyLiftGoal") } }
    /// Miles
    @Published var weeklyRunGoal: Double { didSet { d.set(weeklyRunGoal, forKey: "weeklyRunGoal") } }
    /// Pounds, 0 = none
    @Published var goalWeight: Double { didSet { d.set(goalWeight, forKey: "goalWeight") } }
    /// Pounds per week (negative = losing)
    @Published var goalRate: Double { didSet { d.set(goalRate, forKey: "goalRate") } }
    @Published var onboardingDone: Bool { didSet { d.set(onboardingDone, forKey: "onboardingDone") } }
    /// Lift stats Explore views pinned to Trends, as JSON.
    @Published var savedStatViews: [String] { didSet { d.set(savedStatViews, forKey: "savedStatViews") } }
    @Published var photoLock: Bool { didSet { d.set(photoLock, forKey: "photoLock") } }
    /// Off by default: progress photos are excluded from iCloud/iTunes backup.
    @Published var photoBackup: Bool { didSet { d.set(photoBackup, forKey: "photoBackup") } }
    /// 0 = off
    @Published var photoReminderWeeks: Int { didSet { d.set(photoReminderWeeks, forKey: "photoReminderWeeks") } }
    /// Minutes after midnight.
    @Published var photoReminderMinutes: Int { didSet { d.set(photoReminderMinutes, forKey: "photoReminderMinutes") } }
    @Published var wrappedSeenYear: Int { didSet { d.set(wrappedSeenYear, forKey: "wrappedSeenYear") } }
    @Published var dailyStepGoal: Int { didSet { d.set(dailyStepGoal, forKey: "dailyStepGoal") } }

    init() {
        d.register(defaults: [
            "unit": WeightUnit.lb.rawValue, "barWeightLb": 45.0, "barWeightKg": 20.0,
            "platesLb": [45.0, 25, 10, 5, 2.5], "platesKg": [20.0, 15, 10, 5, 2.5, 1.25],
            "dbMin": 5.0, "dbMax": 100.0, "dbStep": 5.0,
            "defaultRest": 120, "autoStartRest": true, "hapticBeforeEnd": true,
            "upperIncrement": 5.0, "lowerIncrement": 10.0,
            "weeklyLiftGoal": 4, "weeklyRunGoal": 15.0, "goalWeight": 0.0, "goalRate": -0.5,
            "onboardingDone": false,
            "photoLock": false, "photoBackup": false, "photoReminderWeeks": 2, "photoReminderMinutes": 480, "wrappedSeenYear": 0, "dailyStepGoal": 8000,
        ])
        unit = WeightUnit(rawValue: d.string(forKey: "unit") ?? "lb") ?? .lb
        barWeightLb = d.double(forKey: "barWeightLb")
        barWeightKg = d.double(forKey: "barWeightKg")
        platesLb = d.array(forKey: "platesLb") as? [Double] ?? []
        platesKg = d.array(forKey: "platesKg") as? [Double] ?? []
        dumbbellMin = d.double(forKey: "dbMin")
        dumbbellMax = d.double(forKey: "dbMax")
        dumbbellStep = d.double(forKey: "dbStep")
        defaultRest = d.integer(forKey: "defaultRest")
        autoStartRest = d.bool(forKey: "autoStartRest")
        hapticBeforeEnd = d.bool(forKey: "hapticBeforeEnd")
        upperIncrement = d.double(forKey: "upperIncrement")
        lowerIncrement = d.double(forKey: "lowerIncrement")
        weeklyLiftGoal = d.integer(forKey: "weeklyLiftGoal")
        weeklyRunGoal = d.double(forKey: "weeklyRunGoal")
        goalWeight = d.double(forKey: "goalWeight")
        goalRate = d.double(forKey: "goalRate")
        onboardingDone = d.bool(forKey: "onboardingDone")
        savedStatViews = d.stringArray(forKey: "savedStatViews") ?? []
        photoLock = d.bool(forKey: "photoLock")
        photoBackup = d.bool(forKey: "photoBackup")
        photoReminderWeeks = d.integer(forKey: "photoReminderWeeks")
        photoReminderMinutes = d.integer(forKey: "photoReminderMinutes")
        wrappedSeenYear = d.integer(forKey: "wrappedSeenYear")
        dailyStepGoal = d.integer(forKey: "dailyStepGoal")
    }

    static let allPlatesLb: [Double] = [45, 35, 25, 10, 5, 2.5]
    static let allPlatesKg: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25]

    var barWeight: Double { unit == .lb ? barWeightLb : barWeightKg }
    var plates: [Double] { (unit == .lb ? platesLb : platesKg).sorted(by: >) }
}
