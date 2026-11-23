import Foundation
import SwiftData

/// One exercise as performed in one finished workout.
struct Session: Identifiable {
    let entry: WorkoutEntry
    let workout: Workout
    let sets: [SetRecord]
    var id: PersistentIdentifier { entry.persistentModelID }
    var date: Date { workout.startedAt }

    var bestE1RM: Double { sets.filter { $0.reps <= 10 }.map { Analytics.e1RM($0.weight, $0.reps) }.max() ?? 0 }
    var bestE1RMSet: SetRecord? { sets.filter { $0.reps <= 10 }.max { Analytics.e1RM($0.weight, $0.reps) < Analytics.e1RM($1.weight, $1.reps) } }
    var topSet: SetRecord? { sets.max { ($0.weight, $0.reps) < ($1.weight, $1.reps) } }
    var topWeight: Double { sets.map(\.weight).max() ?? 0 }
    var minWeight: Double { sets.map(\.weight).min() ?? 0 }
    var volume: Double { sets.reduce(0) { $0 + $1.weight * Double($1.reps) } }
    var maxReps: Int { sets.map(\.reps).max() ?? 0 }
    var totalReps: Int { sets.reduce(0) { $0 + $1.reps } }
    var longest: Int { sets.map(\.seconds).max() ?? 0 }
    var totalSeconds: Int { sets.reduce(0) { $0 + $1.seconds } }
    var farthest: Double { sets.map(\.distance).max() ?? 0 }

    func heaviest(atLeast distance: Double) -> Double {
        sets.filter { $0.distance + 0.5 >= distance }.map(\.weight).max() ?? 0
    }
}

struct PRResult: Identifiable {
    let id = UUID()
    let exerciseName: String
    let value: String
    let detail: String
    let shortDetail: String
    let date: Date
    let setIndex: Int
}

struct ProgressionConfig {
    var sets: Int
    var repLow: Int
    var repHigh: Int
    var increment: Double
    var targetSeconds: Int
    var targetDistance: Double

    init(_ e: WorkoutEntry) {
        sets = e.targetSets; repLow = e.repLow; repHigh = e.repHigh; increment = e.increment
        targetSeconds = e.targetSeconds; targetDistance = e.targetDistance
    }

    init(_ r: RoutineItem) {
        sets = r.sets; repLow = r.repLow; repHigh = r.repHigh; increment = r.increment
        targetSeconds = r.targetSeconds; targetDistance = r.targetDistance
    }
}

/// What the next session should look like, from double progression.
struct Plan {
    var weight: Double = 0
    var reps: [Int] = []
    var seconds: Int = 0
    var distance: Double = 0
    var progressed = false
    var lastWeight: Double = 0
    var hasHistory = false
    /// e.g. "8+ reps on every set", "2 of 3 sets under 12"
    var reason = ""
    var setsAtTop = 0
    var setsCounted = 0
    /// Every set hit the top of the range, but at least one was logged above RPE 9.
    var heldByRPE = false
}

enum Analytics {
    /// Epley estimate; only meaningful for sets of 10 reps or fewer.
    static func e1RM(_ weight: Double, _ reps: Int) -> Double {
        guard reps > 0, weight > 0 else { return 0 }
        return reps == 1 ? weight : weight * (1 + Double(reps) / 30)
    }

    /// Finished sessions for an exercise, oldest first.
    static func sessions(_ exercise: Exercise, excluding: Workout? = nil, before: Date? = nil) -> [Session] {
        exercise.entries.compactMap { entry -> Session? in
            guard let w = entry.workout, w.endedAt != nil else { return nil }
            if let excluding, w.persistentModelID == excluding.persistentModelID { return nil }
            if let before, w.startedAt >= before { return nil }
            let sets = entry.doneWorkingSets
            guard !sets.isEmpty else { return nil }
            return Session(entry: entry, workout: w, sets: sets)
        }
        .sorted { $0.date < $1.date }
    }

    /// The headline metric used for sparklines and the Lift list.
    static func primary(_ kind: ExerciseKind, _ s: Session) -> Double {
        switch kind {
        case .weightReps: return s.bestE1RM > 0 ? s.bestE1RM : s.topWeight
        case .bodyweight: return Double(s.maxReps)
        case .assisted: return -s.minWeight
        case .timed: return Double(s.longest)
        case .distanceWeight: return s.topWeight
        }
    }

    static func headline(_ ex: Exercise, _ sessions: [Session]) -> (value: String, caption: String)? {
        guard !sessions.isEmpty else { return nil }
        switch ex.kind {
        case .weightReps:
            let best = sessions.map(\.bestE1RM).max() ?? 0
            if best > 0 { return (Fmt.wu(best.rounded()), "est. 1RM") }
            return (Fmt.wu(sessions.map(\.topWeight).max() ?? 0), "top set")
        case .bodyweight:
            return ("\(sessions.map(\.maxReps).max() ?? 0) reps", "max")
        case .assisted:
            return ("−\(Fmt.wu(sessions.map(\.minWeight).min() ?? 0))", "least assist")
        case .timed:
            return (Fmt.clock(sessions.map(\.longest).max() ?? 0), "longest")
        case .distanceWeight:
            let best = sessions.max { $0.topWeight < $1.topWeight }
            let set = best?.sets.max { $0.weight < $1.weight }
            return (Fmt.wu(set?.weight ?? 0), "× \(Fmt.dist(set?.distance ?? 0)) \(Units.distanceLabel)")
        }
    }

    static func setText(_ set: SetRecord, _ kind: ExerciseKind) -> String {
        switch kind {
        case .weightReps: return "\(Fmt.w(set.weight)) × \(set.reps)"
        case .bodyweight: return set.weight > 0 ? "+\(Fmt.w(set.weight)) × \(set.reps)" : "\(set.reps)"
        case .assisted: return "−\(Fmt.w(set.weight)) × \(set.reps)"
        case .timed: return set.weight > 0 ? "+\(Fmt.w(set.weight)) · \(Fmt.clock(set.seconds))" : Fmt.clock(set.seconds)
        case .distanceWeight: return "\(Fmt.w(set.weight)) × \(Fmt.dist(set.distance)) \(Units.distanceLabel)"
        }
    }

    // MARK: PRs

    /// Whether `set` beats everything in `prior` (sessions before this workout). No PRs on the first session.
    static func pr(for set: SetRecord, kind: ExerciseKind, prior: [Session], name: String, date: Date, index: Int) -> PRResult? {
        guard set.done, !set.isWarmup, !prior.isEmpty else { return nil }
        let all = prior.flatMap(\.sets)
        switch kind {
        case .weightReps:
            guard set.weight > 0, set.reps > 0 else { return nil }
            let priorBest = all.filter { $0.reps <= 10 }.max { e1RM($0.weight, $0.reps) < e1RM($1.weight, $1.reps) }
            let priorAtReps = all.filter { $0.reps >= set.reps }.map(\.weight).max() ?? 0
            let isE1RM = set.reps <= 10 && e1RM(set.weight, set.reps) > (priorBest.map { e1RM($0.weight, $0.reps) } ?? 0) + 0.01
            let isRep = priorAtReps > 0 && set.weight > priorAtReps
            guard isE1RM || isRep else { return nil }
            let was = priorBest.map { "was \(Fmt.w($0.weight)) × \($0.reps)" } ?? ""
            return PRResult(exerciseName: name, value: "\(Fmt.w(set.weight)) × \(set.reps)",
                            detail: "Best at \(set.reps) reps\(was.isEmpty ? "" : " · \(was)")", shortDetail: "\(set.reps)-rep best", date: date, setIndex: index)
        case .bodyweight:
            let maxReps = all.map(\.reps).max() ?? 0
            if set.reps > maxReps {
                return PRResult(exerciseName: name, value: "\(set.reps) reps", detail: "Max reps · was \(maxReps)", shortDetail: "max reps", date: date, setIndex: index)
            }
            let addedAtReps = all.filter { $0.reps >= set.reps }.map(\.weight).max() ?? 0
            if set.weight > 0, set.weight > addedAtReps {
                return PRResult(exerciseName: name, value: "+\(Fmt.w(set.weight)) × \(set.reps)", detail: "Most added weight at \(set.reps) reps", shortDetail: "added weight", date: date, setIndex: index)
            }
            return nil
        case .assisted:
            let leastAtReps = all.filter { $0.reps >= set.reps }.map(\.weight).min()
            guard let leastAtReps, set.weight < leastAtReps else { return nil }
            return PRResult(exerciseName: name, value: "−\(Fmt.w(set.weight)) × \(set.reps)", detail: "Least assist · was −\(Fmt.w(leastAtReps))", shortDetail: "least assist", date: date, setIndex: index)
        case .timed:
            let longest = all.map(\.seconds).max() ?? 0
            guard set.seconds > longest else { return nil }
            return PRResult(exerciseName: name, value: Fmt.clock(set.seconds), detail: "Longest hold · was \(Fmt.clock(longest))", shortDetail: "longest hold", date: date, setIndex: index)
        case .distanceWeight:
            let heaviest = all.filter { $0.distance + 0.5 >= set.distance }.map(\.weight).max() ?? 0
            if heaviest > 0, set.weight > heaviest {
                return PRResult(exerciseName: name, value: "\(Fmt.w(set.weight)) × \(Fmt.dist(set.distance)) \(Units.distanceLabel)",
                                detail: "Heaviest at \(Fmt.dist(set.distance)) \(Units.distanceLabel) · was \(Fmt.wu(heaviest))", shortDetail: "heaviest carry", date: date, setIndex: index)
            }
            let farthest = all.filter { $0.weight >= set.weight }.map(\.distance).max() ?? 0
            if farthest > 0, set.distance > farthest + 0.5 {
                return PRResult(exerciseName: name, value: "\(Fmt.dist(set.distance)) \(Units.distanceLabel) × \(Fmt.wu(set.weight))",
                                detail: "Farthest at \(Fmt.wu(set.weight))", shortDetail: "farthest carry", date: date, setIndex: index)
            }
            return nil
        }
    }

    /// Best PR per exercise in an entry (compared with sessions before its workout).
    static func bestPR(_ entry: WorkoutEntry, prior: [Session]? = nil) -> PRResult? {
        guard let ex = entry.exercise, let workout = entry.workout else { return nil }
        let prior = prior ?? sessions(ex, excluding: workout, before: workout.startedAt)
        let sets = entry.workingSets
        var best: (PRResult, Double)?
        for (i, s) in sets.enumerated() {
            guard let pr = pr(for: s, kind: ex.kind, prior: prior, name: ex.name, date: workout.startedAt, index: i + 1) else { continue }
            let score: Double = ex.kind == .weightReps ? e1RM(s.weight, s.reps) : primaryValue(s, ex.kind)
            if best == nil || score > best!.1 { best = (pr, score) }
        }
        return best?.0
    }

    static func primaryValue(_ s: SetRecord, _ kind: ExerciseKind) -> Double {
        switch kind {
        case .weightReps: e1RM(s.weight, s.reps)
        case .bodyweight: Double(s.reps) * 1000 + s.weight
        case .assisted: Double(s.reps) * 1000 - s.weight
        case .timed: Double(s.seconds)
        case .distanceWeight: s.weight * 1000 + s.distance
        }
    }

    static func workoutPRs(_ w: Workout) -> [PRResult] {
        w.sortedEntries.compactMap { bestPR($0) }
    }

    // MARK: Progression

    static func plan(kind: ExerciseKind, config c: ProgressionConfig, last: Session?) -> Plan {
        var p = Plan()
        guard let last else {
            p.reps = Array(repeating: c.repLow, count: max(1, c.sets))
            p.seconds = c.targetSeconds
            p.distance = c.targetDistance
            return p
        }
        p.hasHistory = true
        let sets = last.sets
        switch kind {
        case .weightReps, .bodyweight, .assisted:
            let working = kind == .assisted ? last.minWeight : last.topWeight
            p.lastWeight = working
            let atWorking = sets.filter { kind == .assisted ? $0.weight <= working + 0.01 : $0.weight >= working - 0.01 }
            let counted = max(c.sets, atWorking.count)
            let atTop = atWorking.filter { $0.reps >= c.repHigh }.count
            p.setsAtTop = atTop
            p.setsCounted = counted
            let reachedTop = atTop >= counted && counted > 0
            let grind = atWorking.contains { $0.rpe > 9 }
            let allHit = reachedTop && !grind
            p.heldByRPE = reachedTop && grind
            if allHit {
                p.progressed = true
                p.weight = kind == .assisted ? max(0, working - c.increment) : working + c.increment
                p.reps = Array(repeating: c.repLow, count: max(1, c.sets))
                p.reason = "\(c.repHigh)+ reps on every set"
            } else {
                p.weight = working
                p.reps = (0..<max(1, c.sets)).map { i in i < sets.count ? sets[i].reps : (sets.last?.reps ?? c.repLow) }
                let logged = atWorking.count
                if p.heldByRPE {
                    p.reason = "\(c.repHigh)+ reps but above RPE 9"
                } else if logged < c.sets {
                    p.reason = "\(logged) of \(c.sets) sets logged"
                } else {
                    p.reason = "\(counted - atTop) of \(counted) sets under \(c.repHigh)"
                }
            }
        case .timed:
            let target = c.targetSeconds > 0 ? c.targetSeconds : (sets.map(\.seconds).min() ?? 30)
            let held = sets.filter { $0.seconds >= target }.count
            p.setsAtTop = held; p.setsCounted = max(c.sets, sets.count)
            p.weight = last.topWeight
            p.lastWeight = Double(target)
            if held >= p.setsCounted {
                p.progressed = true
                p.seconds = target + Int(c.increment > 0 && c.increment < 60 ? c.increment : 10)
                p.reason = "Held \(Fmt.clock(target)) on every set"
            } else {
                p.seconds = target
                p.reason = "\(p.setsCounted - held) of \(p.setsCounted) sets under \(Fmt.clock(target))"
            }
        case .distanceWeight:
            let target = c.targetDistance > 0 ? c.targetDistance : last.farthest
            let covered = sets.filter { $0.distance + 0.5 >= target }.count
            p.setsAtTop = covered; p.setsCounted = max(c.sets, sets.count)
            p.distance = target
            p.lastWeight = last.topWeight
            if covered >= p.setsCounted {
                p.progressed = true
                p.weight = last.topWeight + c.increment
                p.reason = "Full \(Fmt.dist(target)) \(Units.distanceLabel) on every set"
            } else {
                p.weight = last.topWeight
                p.reason = "\(p.setsCounted - covered) of \(p.setsCounted) sets short of \(Fmt.dist(target)) \(Units.distanceLabel)"
            }
        }
        return p
    }

    // MARK: Weeks

    static func weekStart(_ d: Date = Date()) -> Date { Calendar.mondayFirst.startOfWeek(d) }

    static func finished(_ workouts: [Workout]) -> [Workout] { workouts.filter { $0.endedAt != nil } }

    static func workouts(_ all: [Workout], inWeekOf d: Date) -> [Workout] {
        let start = weekStart(d)
        let end = Calendar.mondayFirst.date(byAdding: .day, value: 7, to: start)!
        return finished(all).filter { $0.startedAt >= start && $0.startedAt < end }
    }

    /// Routine after the most recently performed one, in routine order.
    static func nextRoutine(_ routines: [Routine], workouts: [Workout]) -> Routine? {
        let sorted = routines.sorted { $0.order < $1.order }
        guard !sorted.isEmpty else { return nil }
        guard let last = finished(workouts).filter({ $0.routine != nil }).max(by: { $0.startedAt < $1.startedAt })?.routine,
              let idx = sorted.firstIndex(where: { $0.persistentModelID == last.persistentModelID }) else { return sorted.first }
        return sorted[(idx + 1) % sorted.count]
    }
}
