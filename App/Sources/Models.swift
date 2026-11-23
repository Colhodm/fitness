import Foundation
import SwiftData

enum ExerciseKind: String, Codable, CaseIterable, Identifiable {
    case weightReps, bodyweight, assisted, timed, distanceWeight
    var id: String { rawValue }

    var title: String {
        switch self {
        case .weightReps: "Weight × reps"
        case .bodyweight: "Bodyweight"
        case .assisted: "Assisted"
        case .timed: "Timed"
        case .distanceWeight: "Distance + weight"
        }
    }

    var detail: String {
        switch self {
        case .weightReps: "Weight, reps, optional RPE"
        case .bodyweight: "Reps, optional added weight"
        case .assisted: "Assist weight, reps · lower is better"
        case .timed: "Duration, optional weight"
        case .distanceWeight: "Carries, sled pushes"
        }
    }

    var listLabel: String {
        switch self {
        case .weightReps: "Weight × reps"
        case .bodyweight: "Reps (+ lb)"
        case .assisted: "Assisted"
        case .timed: "Timed"
        case .distanceWeight: "Distance + weight"
        }
    }

    var activeLabel: String {
        switch self {
        case .weightReps: "logs weight and reps"
        case .bodyweight: "logs reps and added weight"
        case .assisted: "logs assist weight and reps"
        case .timed: "logs time and optional weight"
        case .distanceWeight: "logs weight and distance"
        }
    }
}

enum Equipment: String, Codable, CaseIterable, Identifiable {
    case barbell, dumbbell, machine, cable, kettlebell, bodyweight, other
    var id: String { rawValue }
    var title: String { rawValue == "bodyweight" ? "Bodyweight" : rawValue.capitalized }
}

enum Muscle: String, Codable, CaseIterable, Identifiable {
    case chest, back, legs, shoulders, biceps, triceps, core, glutes, quads, hamstrings, calves
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var isUpper: Bool { ![.legs, .glutes, .core, .quads, .hamstrings, .calves].contains(self) }
    var isLower: Bool { [.legs, .glutes, .quads, .hamstrings, .calves].contains(self) }
    var group: MuscleGroup {
        switch self {
        case .legs, .glutes, .quads, .hamstrings, .calves: .legs
        case .back: .back
        case .chest: .chest
        case .shoulders, .biceps, .triceps: .shouldersArms
        case .core: .core
        }
    }
}

enum MuscleGroup: String, CaseIterable, Identifiable {
    case legs = "Legs", back = "Back", chest = "Chest", shouldersArms = "Shoulders and arms", core = "Core"
    var id: String { rawValue }
}

@Model
final class Exercise {
    var uuid: UUID = UUID()
    var name: String = ""
    var kindRaw: String = ExerciseKind.weightReps.rawValue
    var equipmentRaw: String = Equipment.barbell.rawValue
    var musclesRaw: [String] = []
    var perSide: Bool = false
    var aliases: [String] = []
    var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \WorkoutEntry.exercise) var entries: [WorkoutEntry] = []
    @Relationship(deleteRule: .cascade, inverse: \RoutineItem.exercise) var routineItems: [RoutineItem] = []

    init(name: String, kind: ExerciseKind, equipment: Equipment, muscles: [Muscle], perSide: Bool = false) {
        self.name = name
        self.kindRaw = kind.rawValue
        self.equipmentRaw = equipment.rawValue
        self.musclesRaw = muscles.map(\.rawValue)
        self.perSide = perSide
    }

    var kind: ExerciseKind {
        get { ExerciseKind(rawValue: kindRaw) ?? .weightReps }
        set { kindRaw = newValue.rawValue }
    }
    var equipment: Equipment {
        get { Equipment(rawValue: equipmentRaw) ?? .other }
        set { equipmentRaw = newValue.rawValue }
    }
    var muscles: [Muscle] {
        get { musclesRaw.compactMap(Muscle.init(rawValue:)) }
        set { musclesRaw = newValue.map(\.rawValue) }
    }
    var isUpperBody: Bool { muscles.first?.isUpper ?? true }

    /// "Barbell", or the main muscle for timed bodyweight holds ("Core").
    var equipmentLabel: String {
        if equipment == .bodyweight && (kind == .timed || kind == .distanceWeight) { return muscles.first?.title ?? "Bodyweight" }
        return equipment.title
    }
}

@Model
final class Routine {
    var uuid: UUID = UUID()
    var name: String = ""
    var order: Int = 0
    var createdAt: Date = Date()
    @Relationship(deleteRule: .cascade, inverse: \RoutineItem.routine) var items: [RoutineItem] = []
    @Relationship(deleteRule: .nullify, inverse: \Workout.routine) var workouts: [Workout] = []

    init(name: String, order: Int) {
        self.name = name
        self.order = order
    }

    var sortedItems: [RoutineItem] { items.sorted { $0.order < $1.order } }
    var lastPerformed: Date? { workouts.filter { $0.endedAt != nil }.map(\.startedAt).max() }
}

@Model
final class RoutineItem {
    var order: Int = 0
    var sets: Int = 3
    var repLow: Int = 8
    var repHigh: Int = 12
    var restSeconds: Int = 120
    /// Stored in pounds.
    var increment: Double = 5
    /// 0 = not in a superset; items sharing a non-zero value are performed back to back.
    var supersetGroup: Int = 0
    var targetSeconds: Int = 0
    /// Meters
    var targetDistance: Double = 0
    var routine: Routine?
    var exercise: Exercise?

    init(order: Int, exercise: Exercise, sets: Int = 3, repLow: Int = 8, repHigh: Int = 12, restSeconds: Int = 120, increment: Double = 5) {
        self.order = order
        self.exercise = exercise
        self.sets = sets
        self.repLow = repLow
        self.repHigh = repHigh
        self.restSeconds = restSeconds
        self.increment = increment
    }
}

@Model
final class Workout {
    var uuid: UUID = UUID()
    var name: String = "Workout"
    var startedAt: Date = Date()
    var endedAt: Date?
    var savedToHealth: Bool = false
    var isImported: Bool = false
    /// Set when logging a workout after the fact; it ends this many minutes after `startedAt`.
    var pastDurationMinutes: Int = 0
    var routine: Routine?
    @Relationship(deleteRule: .cascade, inverse: \WorkoutEntry.workout) var entries: [WorkoutEntry] = []

    init(name: String, startedAt: Date = Date(), routine: Routine? = nil) {
        self.name = name
        self.startedAt = startedAt
        self.routine = routine
    }

    var sortedEntries: [WorkoutEntry] { entries.sorted { $0.order < $1.order } }
    var duration: TimeInterval { (endedAt ?? Date()).timeIntervalSince(startedAt) }
    var isPastLog: Bool { pastDurationMinutes > 0 }
    var completedSets: [SetRecord] { entries.flatMap(\.sets).filter { $0.done && !$0.isWarmup } }
    var volume: Double { entries.reduce(0) { $0 + $1.volume } }
}

@Model
final class WorkoutEntry {
    var order: Int = 0
    var supersetGroup: Int = 0
    var targetSets: Int = 3
    var repLow: Int = 8
    var repHigh: Int = 12
    var restSeconds: Int = 120
    var increment: Double = 5
    var targetSeconds: Int = 0
    var targetDistance: Double = 0
    var workout: Workout?
    var exercise: Exercise?
    @Relationship(deleteRule: .cascade, inverse: \SetRecord.entry) var sets: [SetRecord] = []

    init(order: Int, exercise: Exercise) {
        self.order = order
        self.exercise = exercise
    }

    var sortedSets: [SetRecord] { sets.sorted { $0.order < $1.order } }
    var workingSets: [SetRecord] { sortedSets.filter { !$0.isWarmup } }
    var doneWorkingSets: [SetRecord] { workingSets.filter(\.done) }
    var volume: Double {
        guard let exercise else { return 0 }
        switch exercise.kind {
        case .weightReps, .bodyweight: return doneWorkingSets.reduce(0) { $0 + $1.weight * Double($1.reps) }
        case .distanceWeight: return doneWorkingSets.reduce(0) { $0 + $1.weight * (exercise.perSide ? 2 : 1) }
        default: return 0
        }
    }
}

@Model
final class SetRecord {
    var order: Int = 0
    var isWarmup: Bool = false
    /// Pounds. For assisted exercises this is the assist weight; for bodyweight it is added weight.
    var weight: Double = 0
    var reps: Int = 0
    var seconds: Int = 0
    /// Meters
    var distance: Double = 0
    var done: Bool = false
    var edited: Bool = false
    /// Rate of perceived exertion, 0 = not logged.
    var rpe: Double = 0
    var completedAt: Date?
    var entry: WorkoutEntry?

    init(order: Int, isWarmup: Bool = false, weight: Double = 0, reps: Int = 0, seconds: Int = 0, distance: Double = 0) {
        self.order = order
        self.isWarmup = isWarmup
        self.weight = weight
        self.reps = reps
        self.seconds = seconds
        self.distance = distance
    }
}

/// User's label for a run that came from Apple Health.
@Model
final class RunTag {
    var workoutID: UUID = UUID()
    var kindRaw: String = RunKind.easy.rawValue
    init(workoutID: UUID, kind: RunKind) {
        self.workoutID = workoutID
        self.kindRaw = kind.rawValue
    }
    var kind: RunKind { RunKind(rawValue: kindRaw) ?? .easy }
}

enum RunKind: String, CaseIterable, Identifiable, Codable {
    case easy, tempo, long, intervals, race
    var id: String { rawValue }
    var chip: String { rawValue.capitalized }
    var title: String { self == .intervals ? "Intervals" : "\(rawValue.capitalized) run" }
}

/// Weigh-in logged by hand. Kept locally so it still works when Apple Health access is off.
@Model
final class ManualWeighIn {
    var date: Date = Date()
    var pounds: Double = 0
    var savedToHealth: Bool = false
    init(date: Date, pounds: Double, savedToHealth: Bool) {
        self.date = date
        self.pounds = pounds
        self.savedToHealth = savedToHealth
    }
}

enum PhotoPose: String, CaseIterable, Identifiable, Codable {
    case front, side, back
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// A progress photo. The image lives in the app's own storage (see PhotoStore), stamped with that day's numbers.
@Model
final class ProgressPhoto {
    var uuid: UUID = UUID()
    var date: Date = Date()
    var poseRaw: String = PhotoPose.front.rawValue
    var fileName: String = ""
    /// Pounds; 0 = unknown.
    var weight: Double = 0
    /// Fraction (0.178); 0 = unknown.
    var bodyFat: Double = 0
    var leanMass: Double = 0
    var bench1RM: Double = 0
    var squat1RM: Double = 0

    init(date: Date, pose: PhotoPose, fileName: String) {
        self.date = date
        self.poseRaw = pose.rawValue
        self.fileName = fileName
    }

    var pose: PhotoPose { PhotoPose(rawValue: poseRaw) ?? .front }
}

enum AppSchema {
    static let models: [any PersistentModel.Type] = [Exercise.self, Routine.self, RoutineItem.self, Workout.self, WorkoutEntry.self, SetRecord.self, RunTag.self, ManualWeighIn.self, ProgressPhoto.self]
}
