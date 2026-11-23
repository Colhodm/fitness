import Foundation
import SwiftData

/// The built-in exercise catalog (names and types only, no training data) and the three starter routines.
enum Library {
    struct Def {
        let name: String
        let kind: ExerciseKind
        let equipment: Equipment
        let muscles: [Muscle]
        var perSide = false
        var aliases: [String] = []
    }

    static let exercises: [Def] = [
        Def(name: "Bench Press", kind: .weightReps, equipment: .barbell, muscles: [.chest, .triceps], aliases: ["bench", "bp", "flat bench"]),
        Def(name: "Incline Bench Press", kind: .weightReps, equipment: .barbell, muscles: [.chest, .shoulders], aliases: ["incline bench", "incline"]),
        Def(name: "Incline Dumbbell Press", kind: .weightReps, equipment: .dumbbell, muscles: [.chest, .shoulders], aliases: ["incline db press", "db incline press"]),
        Def(name: "Dumbbell Bench Press", kind: .weightReps, equipment: .dumbbell, muscles: [.chest, .triceps], aliases: ["db bench", "db press"]),
        Def(name: "Overhead Press", kind: .weightReps, equipment: .barbell, muscles: [.shoulders, .triceps], aliases: ["ohp", "press", "military press", "shoulder press"]),
        Def(name: "Dumbbell Shoulder Press", kind: .weightReps, equipment: .dumbbell, muscles: [.shoulders, .triceps], aliases: ["db shoulder press", "db ohp"]),
        Def(name: "Lateral Raise", kind: .weightReps, equipment: .dumbbell, muscles: [.shoulders], aliases: ["lat raise", "side raise", "laterals"]),
        Def(name: "Chest Fly", kind: .weightReps, equipment: .cable, muscles: [.chest], aliases: ["fly", "flyes", "cable fly", "pec deck"]),
        Def(name: "Dip", kind: .bodyweight, equipment: .bodyweight, muscles: [.chest, .triceps], aliases: ["dips"]),
        Def(name: "Push-up", kind: .bodyweight, equipment: .bodyweight, muscles: [.chest, .triceps], aliases: ["pushups", "push ups"]),
        Def(name: "Triceps Pushdown", kind: .weightReps, equipment: .cable, muscles: [.triceps], aliases: ["pushdown", "tricep pushdown", "pushdowns"]),
        Def(name: "Skull Crusher", kind: .weightReps, equipment: .barbell, muscles: [.triceps], aliases: ["skullcrushers", "skull crushers"]),
        Def(name: "Deadlift", kind: .weightReps, equipment: .barbell, muscles: [.back, .hamstrings, .glutes], aliases: ["dl", "deadlifts"]),
        Def(name: "Barbell Row", kind: .weightReps, equipment: .barbell, muscles: [.back], aliases: ["row", "bent over row", "bb row", "rows"]),
        Def(name: "Dumbbell Row", kind: .weightReps, equipment: .dumbbell, muscles: [.back], perSide: true, aliases: ["db row", "one arm row"]),
        Def(name: "Pull-up", kind: .bodyweight, equipment: .bodyweight, muscles: [.back, .biceps], aliases: ["pullups", "pull ups", "pullup"]),
        Def(name: "Chin-up", kind: .bodyweight, equipment: .bodyweight, muscles: [.back, .biceps], aliases: ["chinups", "chin ups", "chins"]),
        Def(name: "Assisted Pull-up", kind: .assisted, equipment: .machine, muscles: [.back, .biceps], aliases: ["assisted pullups"]),
        Def(name: "Lat Pulldown", kind: .weightReps, equipment: .cable, muscles: [.back, .biceps], aliases: ["pulldown", "lat pull", "pulldowns"]),
        Def(name: "Seated Cable Row", kind: .weightReps, equipment: .cable, muscles: [.back], aliases: ["cable row", "seated row"]),
        Def(name: "Face Pull", kind: .weightReps, equipment: .cable, muscles: [.shoulders, .back], aliases: ["face pulls"]),
        Def(name: "Barbell Curl", kind: .weightReps, equipment: .barbell, muscles: [.biceps], aliases: ["curl", "curls", "bb curl"]),
        Def(name: "Dumbbell Curl", kind: .weightReps, equipment: .dumbbell, muscles: [.biceps], aliases: ["db curl", "db curls"]),
        Def(name: "Hammer Curl", kind: .weightReps, equipment: .dumbbell, muscles: [.biceps], aliases: ["hammer curls", "hammers"]),
        Def(name: "Back Squat", kind: .weightReps, equipment: .barbell, muscles: [.quads, .glutes], aliases: ["squat", "squats", "bs"]),
        Def(name: "Front Squat", kind: .weightReps, equipment: .barbell, muscles: [.quads], aliases: ["front squats", "fs"]),
        Def(name: "Romanian Deadlift", kind: .weightReps, equipment: .barbell, muscles: [.hamstrings, .glutes], aliases: ["rdl", "rdls"]),
        Def(name: "Leg Press", kind: .weightReps, equipment: .machine, muscles: [.quads, .glutes], aliases: ["legpress"]),
        Def(name: "Bulgarian Split Squat", kind: .weightReps, equipment: .dumbbell, muscles: [.quads, .glutes], perSide: true, aliases: ["bss", "split squat", "bulgarians"]),
        Def(name: "Walking Lunge", kind: .weightReps, equipment: .dumbbell, muscles: [.quads, .glutes], perSide: true, aliases: ["lunges", "lunge"]),
        Def(name: "Leg Curl", kind: .weightReps, equipment: .machine, muscles: [.hamstrings], aliases: ["hamstring curl", "leg curls"]),
        Def(name: "Leg Extension", kind: .weightReps, equipment: .machine, muscles: [.quads], aliases: ["leg extensions", "extensions"]),
        Def(name: "Hip Thrust", kind: .weightReps, equipment: .barbell, muscles: [.glutes, .hamstrings], aliases: ["hip thrusts", "glute bridge"]),
        Def(name: "Calf Raise", kind: .weightReps, equipment: .machine, muscles: [.calves], aliases: ["calves", "calf raises"]),
        Def(name: "Goblet Squat", kind: .weightReps, equipment: .kettlebell, muscles: [.quads, .glutes], aliases: ["goblet"]),
        Def(name: "Kettlebell Swing", kind: .weightReps, equipment: .kettlebell, muscles: [.glutes, .hamstrings], aliases: ["kb swing", "swings"]),
        Def(name: "Plank", kind: .timed, equipment: .bodyweight, muscles: [.core], aliases: ["planks"]),
        Def(name: "Side Plank", kind: .timed, equipment: .bodyweight, muscles: [.core], perSide: true),
        Def(name: "Dead Hang", kind: .timed, equipment: .bodyweight, muscles: [.back], aliases: ["hang"]),
        Def(name: "Hanging Leg Raise", kind: .bodyweight, equipment: .bodyweight, muscles: [.core], aliases: ["leg raises", "hlr"]),
        Def(name: "Cable Crunch", kind: .weightReps, equipment: .cable, muscles: [.core], aliases: ["crunch", "crunches"]),
        Def(name: "Farmer's Carry", kind: .distanceWeight, equipment: .dumbbell, muscles: [.core, .back], perSide: true, aliases: ["farmers carry", "farmer carry", "farmers walk", "carry"]),
        Def(name: "Sled Push", kind: .distanceWeight, equipment: .other, muscles: [.quads, .glutes], aliases: ["sled"]),
    ]

    struct StarterItem { let name: String; let sets: Int; let low: Int; let high: Int; let rest: Int; var superset = 0; var seconds = 0; var yards = 0.0 }
    struct Starter { let name: String; let blurb: String; let items: [StarterItem] }

    static let starters: [Starter] = [
        Starter(name: "Push", blurb: "Chest, shoulders, triceps", items: [
            StarterItem(name: "Bench Press", sets: 3, low: 5, high: 8, rest: 180),
            StarterItem(name: "Overhead Press", sets: 3, low: 6, high: 8, rest: 150),
            StarterItem(name: "Incline Dumbbell Press", sets: 3, low: 8, high: 12, rest: 120),
            StarterItem(name: "Lateral Raise", sets: 3, low: 12, high: 15, rest: 90, superset: 1),
            StarterItem(name: "Triceps Pushdown", sets: 3, low: 10, high: 12, rest: 90, superset: 1),
            StarterItem(name: "Plank", sets: 3, low: 1, high: 1, rest: 60, seconds: 60),
        ]),
        Starter(name: "Pull", blurb: "Back, biceps", items: [
            StarterItem(name: "Deadlift", sets: 3, low: 3, high: 5, rest: 180),
            StarterItem(name: "Barbell Row", sets: 3, low: 6, high: 8, rest: 120),
            StarterItem(name: "Pull-up", sets: 3, low: 10, high: 12, rest: 120),
            StarterItem(name: "Lat Pulldown", sets: 3, low: 10, high: 12, rest: 90),
            StarterItem(name: "Face Pull", sets: 3, low: 12, high: 15, rest: 90, superset: 1),
            StarterItem(name: "Hammer Curl", sets: 3, low: 10, high: 12, rest: 90, superset: 1),
        ]),
        Starter(name: "Legs", blurb: "Quads, hamstrings, glutes", items: [
            StarterItem(name: "Back Squat", sets: 3, low: 5, high: 8, rest: 180),
            StarterItem(name: "Romanian Deadlift", sets: 3, low: 8, high: 10, rest: 150),
            StarterItem(name: "Leg Press", sets: 3, low: 10, high: 12, rest: 120),
            StarterItem(name: "Leg Curl", sets: 3, low: 10, high: 12, rest: 90),
            StarterItem(name: "Farmer's Carry", sets: 3, low: 1, high: 1, rest: 90, yards: 40),
        ]),
    ]

    /// Inserts the exercise catalog once (and any new catalog entries added in later versions).
    @MainActor
    static func ensureCatalog(_ context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let names = Set(existing.map { $0.name.lowercased() })
        // v2 split "legs" into quads, hamstrings and calves for the catalog exercises.
        if !AppGroup.defaults.bool(forKey: "catalogMusclesV2") {
            for e in existing where e.musclesRaw.contains(Muscle.legs.rawValue) {
                if let def = exercises.first(where: { $0.name.lowercased() == e.name.lowercased() }) { e.muscles = def.muscles }
            }
            AppGroup.defaults.set(true, forKey: "catalogMusclesV2")
        }
        let seeded = AppGroup.defaults.stringArray(forKey: "catalogSeeded") ?? []
        var newSeeded = seeded
        for def in exercises where !names.contains(def.name.lowercased()) && !seeded.contains(def.name) {
            let e = Exercise(name: def.name, kind: def.kind, equipment: def.equipment, muscles: def.muscles, perSide: def.perSide)
            e.aliases = def.aliases
            context.insert(e)
            newSeeded.append(def.name)
        }
        for def in exercises where !newSeeded.contains(def.name) { newSeeded.append(def.name) }
        AppGroup.defaults.set(newSeeded, forKey: "catalogSeeded")
        try? context.save()
    }

    @MainActor
    static func exercise(named name: String, in context: ModelContext) -> Exercise? {
        let all = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        return all.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    @MainActor
    @discardableResult
    static func createStarter(_ starter: Starter, in context: ModelContext) -> Routine {
        let routines = (try? context.fetch(FetchDescriptor<Routine>())) ?? []
        if let r = routines.first(where: { $0.name == starter.name }) { return r }
        let routine = Routine(name: starter.name, order: (routines.map(\.order).max() ?? -1) + 1)
        context.insert(routine)
        let settings = AppSettings.shared
        for (i, item) in starter.items.enumerated() {
            guard let ex = exercise(named: item.name, in: context) else { continue }
            let ri = RoutineItem(order: i, exercise: ex, sets: item.sets, repLow: item.low, repHigh: item.high, restSeconds: item.rest,
                                 increment: ex.isUpperBody ? settings.upperIncrement : settings.lowerIncrement)
            ri.supersetGroup = item.superset
            ri.targetSeconds = item.seconds
            ri.targetDistance = item.yards * Units.metersPerYard
            if ex.kind == .timed { ri.increment = 10 }
            ri.routine = routine
            context.insert(ri)
        }
        try? context.save()
        return routine
    }
}
