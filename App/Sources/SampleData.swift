#if DEBUG
import Foundation
import SwiftData

/// Deterministic pseudo-random numbers so sample screenshots are stable.
struct SeededRandom {
    private var state: UInt64
    init(_ seed: UInt64) { state = seed }
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
    mutating func range(_ a: Double, _ b: Double) -> Double { a + (b - a) * next() }
}

/// DEBUG-only stand-in for Apple Health so the Simulator shows realistic screens. Never used in Release builds.
struct SampleHealth {
    var weights: [BodySample] = []
    var bodyFat: [BodySample] = []
    var lean: [BodySample] = []
    var runs: [RunSummary] = []
    private var paces: [UUID: [Double]] = [:]

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-sampleData") || AppGroup.defaults.bool(forKey: "debugSampleData")
    }
    static func flag(_ name: String) -> Bool { ProcessInfo.processInfo.arguments.contains(name) }

    static func make(now: Date = Date()) -> SampleHealth {
        var rng = SeededRandom(42)
        var s = SampleHealth()
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let days = 250
        let stale = flag("-staleRenpho")
        for i in stride(from: days, through: 0, by: -1) {
            if stale && i < 4 { continue }
            if i > 0 && rng.next() < 0.14 { continue }
            let day = cal.date(byAdding: .day, value: -i, to: today)!
            let t = Double(days - i) / Double(days)
            let base = 193.6 - 12.0 * t + 0.35 * sin(Double(i) / 9)
            let w = i == 0 ? 181.8 : base + rng.range(-0.7, 0.7)
            let date = day.addingTimeInterval(7 * 3600 + 12 * 60 - (stale && i == 4 ? 4 * 60 : 0))
            s.weights.append(BodySample(date: date, value: (w * 10).rounded() / 10, source: "Renpho"))
            let lean = 148.6 + 1.3 * t + rng.range(-0.5, 0.5)
            s.bodyFat.append(BodySample(date: date, value: 1 - lean / w, source: "Renpho"))
            s.lean.append(BodySample(date: date, value: lean, source: "Renpho"))
        }
        if !stale {
            s.weights.append(BodySample(date: cal.date(byAdding: .day, value: -2, to: today)!.addingTimeInterval(7.5 * 3600), value: 182.2, source: "Manual entry", isManual: true))
        }
        if !flag("-noRuns") {
            let weekStart = Analytics.weekStart(now)
            // (days after week start, kind, miles, pace sec/mi)
            let thisWeek: [(Int, Double, Double, Int, Int)] = [(1, 6.2, 472, 18, 7), (3, 5.0, 545, 20, 9)]
            var all: [(Date, Double, Double)] = []
            for (dayOffset, miles, pace, h, m) in thisWeek {
                let d = cal.date(byAdding: .day, value: dayOffset, to: weekStart)!.addingTimeInterval(Double(h * 3600 + m * 60))
                if d < now { all.append((d, miles, pace)) }
            }
            let lastWeek = cal.date(byAdding: .day, value: -7, to: weekStart)!
            all.append((cal.date(byAdding: .day, value: 6, to: lastWeek)!.addingTimeInterval(7 * 3600 + 4 * 60), 8.02, 514))
            all.append((cal.date(byAdding: .day, value: 4, to: lastWeek)!.addingTimeInterval(6.5 * 3600), 4.0, 550))
            all.append((cal.date(byAdding: .day, value: 2, to: lastWeek)!.addingTimeInterval(18 * 3600), 5.5, 460))
            all.append((cal.date(byAdding: .day, value: 0, to: lastWeek)!.addingTimeInterval(7 * 3600), 5.5, 548))
            for w in 2...24 {
                let ws = cal.date(byAdding: .day, value: -7 * w, to: weekStart)!
                let total = w > 20 ? 14.0 : 19 + rng.range(-3, 6)
                let count = w > 20 ? 3 : 4
                for k in 0..<count {
                    let miles = k == count - 1 ? total * 0.36 : total * 0.64 / Double(count - 1)
                    all.append((cal.date(byAdding: .day, value: [0, 2, 4, 6][k], to: ws)!.addingTimeInterval(7 * 3600), (miles * 10).rounded() / 10, rng.range(500, 560)))
                }
            }
            for (d, miles, pace) in all {
                let id = UUID()
                let meters = miles * Units.metersPerMile
                let n = Int(miles.rounded(.up))
                var splits: [Double] = []
                for k in 0..<n { splits.append(pace + 18 - Double(k) * 36 / Double(max(1, n - 1)) + rng.range(-4, 4)) }
                let duration = zip(splits, (0..<n).map { k in min(1, miles - Double(k)) }).reduce(0) { $0 + $1.0 * $1.1 }
                s.runs.append(RunSummary(id: id, start: d, end: d.addingTimeInterval(duration), duration: duration, meters: meters,
                                         avgHR: 140 + (pace < 480 ? 14 : 8) + rng.range(-3, 3), source: "Apple Watch"))
                s.paces[id] = splits
            }
        }
        return s
    }

    func detail(for run: RunSummary) -> RunDetail {
        let splits = paces[run.id] ?? []
        let miles = Units.runDisplay(run.meters)
        var d = RunDetail()
        var hr = 141.0
        d.splits = splits.enumerated().map { i, p in
            hr += 2.3
            let frac = min(1, miles - Double(i))
            return RunSplit(index: i + 1, seconds: p, fraction: frac, hr: hr)
        }
        d.avgHR = run.avgHR
        // A loop in Golden Gate Park: out along a gentle arc, round a turn, and back.
        let center = (lat: 37.7694, lon: -122.4862)
        let count = 200
        var t = run.start
        for i in 0...count {
            let a = Double(i) / Double(count)
            let theta = a * 2 * .pi * 0.92 + .pi
            let lat = center.lat + 0.0062 * sin(theta) * (0.65 + 0.35 * a)
            let lon = center.lon + 0.0175 * cos(theta) * (0.8 + 0.2 * sin(a * .pi))
            d.route.append(RoutePoint(latitude: lat, longitude: lon, time: t))
            let splitIndex = min(splits.count - 1, Int(a * miles))
            t = t.addingTimeInterval((splits.isEmpty ? 500 : splits[max(0, splitIndex)]) * miles / Double(count))
        }
        return d
    }
}

enum SampleLifting {
    /// Seeds ~12 weeks of Push/Pull/Legs history with double progression. DEBUG only.
    @MainActor
    static func seed(_ context: ModelContext, now: Date = Date()) {
        guard ((try? context.fetchCount(FetchDescriptor<Workout>())) ?? 0) == 0 else { return }
        var rng = SeededRandom(7)
        let routines = Library.starters.map { Library.createStarter($0, in: context) }
        // Starting weights (lb) / reps 12 weeks ago.
        let start: [String: (Double, Int)] = [
            "Bench Press": (180, 5), "Overhead Press": (95, 6), "Incline Dumbbell Press": (50, 8), "Lateral Raise": (15, 12),
            "Triceps Pushdown": (40, 10), "Plank": (0, 0), "Deadlift": (275, 3), "Barbell Row": (130, 6), "Pull-up": (0, 9),
            "Lat Pulldown": (110, 10), "Face Pull": (35, 12), "Hammer Curl": (25, 10), "Back Squat": (245, 5),
            "Romanian Deadlift": (185, 8), "Leg Press": (270, 10), "Leg Curl": (80, 10), "Farmer's Carry": (50, 0),
        ]
        var state: [String: (w: Double, reps: [Int], secs: Int)] = [:]
        for (k, v) in start { state[k] = (v.0, [v.1, v.1, max(1, v.1 - 1)], 90) }
        let cal = Calendar.current
        let weekStart = Analytics.weekStart(now)
        var dates: [(Date, Routine)] = []
        var idx = 0
        for w in stride(from: 12, through: 0, by: -1) {
            let ws = cal.date(byAdding: .day, value: -7 * w, to: weekStart)!
            for dayOffset in [0, 1, 3, 5] {
                let d = cal.date(byAdding: .day, value: dayOffset, to: ws)!.addingTimeInterval(17.5 * 3600)
                if d >= cal.startOfDay(for: now) { continue }
                if w > 0 && dayOffset == 5 && rng.next() < 0.5 { continue }
                dates.append((d, routines[idx % 3]))
                idx += 1
            }
        }
        for (date, routine) in dates {
            let wk = Workout(name: "\(routine.name) Day", startedAt: date, routine: routine)
            context.insert(wk)
            var minutes = 0.0
            for item in routine.sortedItems {
                guard let ex = item.exercise, var st = state[ex.name] else { continue }
                let entry = WorkoutEntry(order: item.order, exercise: ex)
                entry.targetSets = item.sets; entry.repLow = item.repLow; entry.repHigh = item.repHigh
                entry.restSeconds = item.restSeconds; entry.increment = item.increment; entry.supersetGroup = item.supersetGroup
                entry.targetSeconds = ex.kind == .timed ? st.secs : 0
                entry.targetDistance = item.targetDistance
                entry.workout = wk
                context.insert(entry)
                for i in 0..<item.sets {
                    let s = SetRecord(order: i)
                    switch ex.kind {
                    case .timed: s.seconds = st.secs + (i == 0 ? 0 : -Int(rng.range(0, 12)))
                    case .distanceWeight: s.weight = st.w; s.distance = item.targetDistance; s.reps = 1
                    default:
                        s.weight = st.w; s.reps = st.reps[min(i, st.reps.count - 1)]
                        if rng.next() < 0.7 { s.rpe = min(10, (7 + rng.range(0, 3.5)).rounded(.down) + Double(i / 2)) }
                    }
                    s.done = true; s.completedAt = date.addingTimeInterval(Double(i) * 150)
                    s.entry = entry
                    context.insert(s)
                }
                minutes += Double(item.sets) * Double(item.restSeconds + 45) / 60
                // Progress for next time.
                switch ex.kind {
                case .timed: st.secs = min(130, st.secs + 4)
                case .distanceWeight: if rng.next() < 0.45 { st.w = min(70, st.w + 5) }
                case .bodyweight:
                    st.reps = st.reps.enumerated().map { i, r in min(13, r + (rng.next() < (i == 0 ? 0.45 : 0.3) ? 1 : 0)) }
                default:
                    if st.reps.allSatisfy({ $0 >= item.repHigh }) {
                        st.w += item.increment
                        st.reps = Array(repeating: item.repLow, count: 3)
                    } else {
                        st.reps = st.reps.map { min(item.repHigh, $0 + (rng.next() < 0.7 ? 1 : 0)) }
                    }
                }
                state[ex.name] = st
            }
            wk.endedAt = date.addingTimeInterval(max(45, minutes) * 60)
            wk.savedToHealth = true
        }
        try? context.save()
    }

    @MainActor
    static func eraseAll(_ context: ModelContext) {
        try? context.delete(model: Workout.self)
        try? context.delete(model: Routine.self)
        try? context.delete(model: RunTag.self)
        try? context.delete(model: ManualWeighIn.self)
        try? context.save()
    }
}
#endif

#if DEBUG
extension WorkoutSession {
    /// Logs the first `sets` working sets of the routine (one extra rep so a PR shows), leaving a rest timer running. DEBUG only.
    func demoProgress(sets: Int) {
        guard let w = workout else { return }
        if let start = Calendar.current.date(byAdding: .minute, value: -32, to: Date()) { w.startedAt = start }
        var remaining = sets
        for entry in w.sortedEntries {
            for s in entry.sortedSets where remaining > 0 && !s.done {
                if entry.order == 1 && s.order > 0 { s.reps += 1; s.edited = true }
                log(s)
                remaining -= 1
            }
            if remaining == 0 { break }
        }
        RestTimer.shared.start(seconds: 84)
    }
}
#endif
