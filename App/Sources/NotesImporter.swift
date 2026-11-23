import Foundation
import SwiftData

/// Parses free-text lifting notes ("Bench 205x5, 205x5", "Pullups 12, 10, 9", "Row 155x8x3").
enum NotesImporter {
    struct Token: Hashable {
        var numbers: [Double]
        var added = false
        var seconds: Int?
        var isDistance = false
        var atWeight: Double?
        /// Explicit unit written in the note ("kg"/"lb", "m"/"yd"/"ft"); nil means use the app's units.
        var weightUnit: WeightUnit?
        var metersPerUnit: Double?
    }

    struct Line: Identifiable, Hashable {
        let id = UUID()
        var rawName: String
        var tokens: [Token]
    }

    struct ParsedWorkout: Identifiable {
        let id = UUID()
        var date: Date
        var lines: [Line]
    }

    struct ParsedSet { var weight = 0.0; var reps = 0; var seconds = 0; var distance = 0.0 }

    // MARK: Parsing

    static func parse(_ text: String, now: Date = Date()) -> [ParsedWorkout] {
        var out: [ParsedWorkout] = []
        var current: ParsedWorkout?
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if let d = date(from: line, now: now) {
                if let c = current, !c.lines.isEmpty { out.append(c) }
                current = ParsedWorkout(date: d, lines: [])
                continue
            }
            guard let parsed = exerciseLine(line) else { continue }
            if current == nil { current = ParsedWorkout(date: Calendar.current.startOfDay(for: now), lines: []) }
            current?.lines.append(parsed)
        }
        if let c = current, !c.lines.isEmpty { out.append(c) }
        return out
    }

    private static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

    static func date(from line: String, now: Date) -> Date? {
        let l = line.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " :-"))
        let cal = Calendar.current
        var y: Int?, m: Int?, d: Int?
        if let r = l.firstMatch(of: /^(?:(?:mon|tue|wed|thu|fri|sat|sun)[a-z]*,?\s+)?([a-z]{3,9})\.?\s+(\d{1,2})(?:st|nd|rd|th)?(?:,?\s+(\d{4}))?$/) {
            let name = String(r.1.prefix(3))
            guard let mi = months.firstIndex(of: name) else { return nil }
            m = mi + 1; d = Int(r.2); y = r.3.flatMap { Int($0) }
        } else if let r = l.firstMatch(of: /^(\d{4})-(\d{1,2})-(\d{1,2})$/) {
            y = Int(r.1); m = Int(r.2); d = Int(r.3)
        } else if let r = l.firstMatch(of: /^(?:(?:mon|tue|wed|thu|fri|sat|sun)[a-z]*,?\s+)?(\d{1,2})\/(\d{1,2})(?:\/(\d{2,4}))?$/) {
            m = Int(r.1); d = Int(r.2)
            if let ys = r.3, let yy = Int(ys) { y = yy < 100 ? 2000 + yy : yy }
        } else {
            return nil
        }
        guard let m, let d, (1...12).contains(m), (1...31).contains(d) else { return nil }
        var comps = DateComponents(year: y ?? cal.component(.year, from: now), month: m, day: d, hour: 18)
        guard var date = cal.date(from: comps) else { return nil }
        if y == nil, date > now.addingTimeInterval(86400) {
            comps.year! -= 1
            date = cal.date(from: comps) ?? date
        }
        return date
    }

    static func exerciseLine(_ line: String) -> Line? {
        // Name is everything before the first token that starts with a digit, "+" or "-" followed by a digit.
        guard let r = line.firstMatch(of: /^(.*?[A-Za-z][^0-9+]*?)[\s:\-–]+([+]?\d.*)$/) else { return nil }
        let name = String(r.1).trimmingCharacters(in: CharacterSet(charactersIn: " :-–")).trimmingCharacters(in: .whitespaces)
        let rest = String(r.2)
        var tokens: [Token] = []
        for piece in rest.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "/" }) {
            let p = piece.trimmingCharacters(in: .whitespaces).lowercased()
            if p.isEmpty { continue }
            if let t = token(p) { tokens.append(t) }
            else {
                for sub in p.split(separator: " ") { if let t = token(String(sub)) { tokens.append(t) } }
            }
        }
        guard !name.isEmpty, !tokens.isEmpty else { return nil }
        return Line(rawName: name, tokens: tokens)
    }

    static func token(_ p: String) -> Token? {
        let lower = p.lowercased()
        let unit: WeightUnit? = lower.contains("kg") ? .kg : (lower.contains("lb") ? .lb : nil)
        guard var t = rawToken(p) else { return nil }
        t.weightUnit = unit
        return t
    }

    private static func rawToken(_ p: String) -> Token? {
        let s = p.replacingOccurrences(of: "×", with: "x").replacingOccurrences(of: "*", with: "x").replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "lbs", with: "").replacingOccurrences(of: "lb", with: "").replacingOccurrences(of: "kg", with: "")
        if let r = s.firstMatch(of: /^(\d+)x(\d+)@(\d+(?:\.\d+)?)$/) {
            return Token(numbers: [Double(r.3)!, Double(r.2)!, Double(r.1)!], atWeight: Double(r.3))
        }
        if let r = s.firstMatch(of: /^(\d+):(\d{2})$/) {
            return Token(numbers: [], seconds: Int(r.1)! * 60 + Int(r.2)!)
        }
        if let r = s.firstMatch(of: /^(\+)?(\d+(?:\.\d+)?)(?:x(\d+(?:\.\d+)?))?(?:x(\d+))?(yd|yds|m|ft)?$/) {
            var nums = [Double(r.2)!]
            if let b = r.3 { nums.append(Double(b)!) }
            if let c = r.4 { nums.append(Double(c)!) }
            var t = Token(numbers: nums, added: r.1 != nil, isDistance: r.5 != nil)
            if let u = r.5 { t.metersPerUnit = u == "m" ? 1 : Units.metersPerYard }
            if let u = r.5, u == "ft", nums.count > 1 { t.numbers[1] = nums[1] / 3 }
            return t
        }
        if let r = s.firstMatch(of: /^(\d+)s(?:ec)?$/) { return Token(numbers: [], seconds: Int(r.1)!) }
        return nil
    }

    /// Turns tokens into sets for a given exercise type.
    static func sets(_ line: Line, kind: ExerciseKind) -> [ParsedSet] {
        var out: [ParsedSet] = []
        var lastWeight = 0.0
        let distUnit = AppSettings.shared.unit == .lb ? Units.metersPerYard : 1
        for t in line.tokens {
            if let secs = t.seconds {
                out.append(ParsedSet(weight: kind == .timed ? 0 : lastWeight, reps: kind == .timed ? 0 : 1, seconds: secs))
                continue
            }
            let n = t.numbers
            func wt(_ v: Double) -> Double {
                switch t.weightUnit {
                case .kg: v * 2.2046226218
                case .lb: v
                case nil: Units.pounds(fromDisplay: v)
                }
            }
            switch kind {
            case .weightReps, .assisted:
                if n.count == 1 {
                    out.append(ParsedSet(weight: lastWeight, reps: Int(n[0])))
                } else {
                    lastWeight = wt(n[0])
                    let count = n.count > 2 ? Int(n[2]) : 1
                    for _ in 0..<max(1, min(count, 20)) { out.append(ParsedSet(weight: lastWeight, reps: Int(n[1]))) }
                }
            case .bodyweight:
                if n.count == 1 { out.append(ParsedSet(weight: t.added ? wt(n[0]) : 0, reps: Int(n[0]))) }
                else if t.added || n.count == 3 {
                    let count = n.count > 2 ? Int(n[2]) : 1
                    for _ in 0..<max(1, min(count, 20)) { out.append(ParsedSet(weight: wt(n[0]), reps: Int(n[1]))) }
                } else {
                    for _ in 0..<max(1, min(Int(n[0]), 20)) { out.append(ParsedSet(weight: 0, reps: Int(n[1]))) }
                }
            case .timed:
                if n.count >= 1 { out.append(ParsedSet(seconds: Int(n[0]))) }
            case .distanceWeight:
                if n.count >= 2 {
                    let count = n.count > 2 ? Int(n[2]) : 1
                    for _ in 0..<max(1, min(count, 20)) { out.append(ParsedSet(weight: wt(n[0]), reps: 1, distance: n[1] * (t.metersPerUnit ?? distUnit))) }
                }
            }
        }
        return out
    }

    // MARK: Matching

    private static let expansions: [String: String] = [
        "db": "dumbbell", "bb": "barbell", "kb": "kettlebell", "inc": "incline", "incl": "incline", "ext": "extension",
        "lat": "lat", "ohp": "overhead press", "rdl": "romanian deadlift", "dl": "deadlift", "bp": "bench press",
    ]

    static func normalize(_ s: String) -> String {
        let lowered = s.lowercased().replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "'", with: "")
        let words = lowered.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        return words.map { w in
            var w = w
            if w.count > 3, w.hasSuffix("s"), !w.hasSuffix("ss") { w.removeLast() }
            return w
        }.joined(separator: " ")
    }

    private static func squash(_ s: String) -> String { normalize(s).replacingOccurrences(of: " ", with: "") }

    static func match(_ raw: String, in exercises: [Exercise]) -> Exercise? {
        let key = squash(raw)
        if let e = exercises.first(where: { squash($0.name) == key || $0.aliases.contains { squash($0) == key } }) { return e }
        let expanded = normalize(raw).split(separator: " ").map { expansions[String($0)] ?? String($0) }.joined(separator: " ")
        let words = Set(expanded.split(separator: " ").map(String.init))
        guard !words.isEmpty else { return nil }
        let candidates = exercises.filter { e in
            let ew = Set(normalize(e.name).split(separator: " ").map(String.init))
            return words.isSubset(of: ew)
        }
        return candidates.count == 1 ? candidates[0] : nil
    }

    static func remember(alias raw: String, for exercise: Exercise) {
        let n = normalize(raw)
        guard squash(raw) != squash(exercise.name), !exercise.aliases.contains(where: { normalize($0) == n }) else { return }
        exercise.aliases.append(n)
    }

    /// Creates finished workouts from parsed notes. Returns number of sets imported.
    @MainActor
    static func importWorkouts(_ parsed: [ParsedWorkout], mapping: [String: Exercise], into context: ModelContext) -> Int {
        var count = 0
        for pw in parsed {
            let lines = pw.lines.filter { mapping[$0.rawName.lowercased()] != nil }
            guard !lines.isEmpty else { continue }
            let w = Workout(name: "Imported workout", startedAt: pw.date)
            w.endedAt = pw.date.addingTimeInterval(3600)
            w.isImported = true
            context.insert(w)
            for (i, line) in lines.enumerated() {
                let ex = mapping[line.rawName.lowercased()]!
                remember(alias: line.rawName, for: ex)
                let entry = WorkoutEntry(order: i, exercise: ex)
                let sets = Self.sets(line, kind: ex.kind)
                entry.targetSets = sets.count
                switch ex.kind {
                case .timed: entry.repLow = 1; entry.repHigh = 1; entry.targetSeconds = sets.map(\.seconds).min() ?? 0; entry.increment = 10
                case .distanceWeight: entry.repLow = 1; entry.repHigh = 1; entry.targetDistance = sets.map(\.distance).max() ?? 0
                default:
                    let reps = sets.map(\.reps)
                    entry.repLow = max(1, (reps.min() ?? 8))
                    entry.repHigh = max(entry.repLow, reps.max() ?? 12)
                    entry.increment = ex.isUpperBody ? AppSettings.shared.upperIncrement : AppSettings.shared.lowerIncrement
                }
                entry.restSeconds = AppSettings.shared.defaultRest
                entry.workout = w
                context.insert(entry)
                for (j, ps) in sets.enumerated() {
                    let s = SetRecord(order: j, weight: ps.weight, reps: ps.reps, seconds: ps.seconds, distance: ps.distance)
                    s.done = true
                    s.completedAt = pw.date
                    s.entry = entry
                    context.insert(s)
                    count += 1
                }
            }
        }
        try? context.save()
        return count
    }
}
