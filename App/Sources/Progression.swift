import SwiftUI

/// Where a rep-based lift stands on double progression, and when it's likely to move up.
struct Guidance {
    enum Status { case ready, tooEasy, building, stalled, start, grind }

    var status: Status
    /// Working weight of the last session (assistance for assisted lifts).
    var weight: Double
    /// Weight the next step up uses.
    var nextWeight: Double
    var repHigh: Int
    var repLow: Int
    var sets: Int
    /// Reps at the working weight, each set capped at the top of the range.
    var lastTotal: Int
    var target: Int
    /// Total reps per session at the current weight, oldest first.
    var ladder: [(date: Date, reps: Int)]
    var perSession: Double?
    var sessionsLeft: Int?
    var eta: Date?

    var repsToGo: Int { max(0, target - lastTotal) }
    var progress: Double { Double(lastTotal) / Double(max(1, target)) }
}

enum Progression {
    static let repKinds: Set<ExerciseKind> = [.weightReps, .bodyweight, .assisted]

    /// `sessions` are finished sessions of the lift, oldest first. nil for timed/carry lifts or no history.
    static func guidance(kind: ExerciseKind, config c: ProgressionConfig, sessions: [Session]) -> Guidance? {
        guard repKinds.contains(kind), let last = sessions.last, c.sets > 0, c.repHigh > 0 else { return nil }
        let plan = Analytics.plan(kind: kind, config: c, last: last)
        let assisted = kind == .assisted
        let working = plan.lastWeight
        func atWorking(_ s: Session) -> [SetRecord] {
            s.sets.filter { abs((assisted ? s.minWeight : s.topWeight) - working) < 0.01 && abs($0.weight - working) < 0.01 }
        }
        func total(_ s: Session) -> Int {
            atWorking(s).map { min($0.reps, c.repHigh) }.sorted(by: >).prefix(c.sets).reduce(0, +)
        }
        var run: [Session] = []
        for s in sessions.reversed() {
            guard !atWorking(s).isEmpty else { break }
            run.insert(s, at: 0)
        }
        let ladder = run.suffix(8).map { (date: $0.date, reps: total($0)) }
        let target = c.sets * c.repHigh
        let lastTotal = total(last)
        let up = assisted ? max(0, working - c.increment) : working + c.increment
        var g = Guidance(status: .building, weight: working, nextWeight: up, repHigh: c.repHigh, repLow: c.repLow, sets: c.sets,
                         lastTotal: lastTotal, target: target, ladder: ladder)
        if plan.progressed {
            let blewPast = atWorking(last).filter { $0.reps >= c.repHigh + 3 }.count >= c.sets
            g.status = blewPast ? .tooEasy : .ready
            return g
        }
        if plan.heldByRPE { g.status = .grind; return g }
        if run.count == 1, sessions.count > 1 { g.status = .start }
        let totals = run.map(total)
        if totals.count >= 3, totals.last! <= totals[totals.count - 3] {
            g.status = .stalled
            return g
        }
        // Least-squares slope of total reps per session over the recent run at this weight.
        let recent = Array(totals.suffix(5))
        if recent.count >= 2 {
            let n = Double(recent.count)
            let xs = (0..<recent.count).map(Double.init)
            let mx = xs.reduce(0, +) / n, my = recent.map(Double.init).reduce(0, +) / n
            let num = zip(xs, recent).reduce(0) { $0 + ($1.0 - mx) * (Double($1.1) - my) }
            let den = xs.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }
            let slope = den > 0 ? num / den : 0
            if slope > 0.05 {
                g.perSession = slope
                let left = max(1, Int((Double(target - lastTotal) / slope).rounded(.up)))
                g.sessionsLeft = left
                let dates = sessions.suffix(6).map(\.date)
                let gaps = zip(dates.dropFirst(), dates).map { $0.timeIntervalSince($1) }.sorted()
                if !gaps.isEmpty { g.eta = last.date.addingTimeInterval(gaps[gaps.count / 2] * Double(left)) }
            }
        }
        return g
    }

    static func weightText(_ w: Double, kind: ExerciseKind) -> String {
        switch kind {
        case .assisted: "−\(Fmt.w(w)) assist"
        case .bodyweight: w > 0 ? "+\(Fmt.w(w))" : "bodyweight"
        default: Fmt.w(w)
        }
    }

    static func headline(_ g: Guidance, kind: ExerciseKind) -> String {
        let next = weightText(g.nextWeight, kind: kind)
        switch g.status {
        case .ready: return "Ready: \(next) next session"
        case .tooEasy: return "Ready: \(next) next session"
        case .stalled: return "Stalled at \(weightText(g.weight, kind: kind))"
        case .grind: return "Hold \(weightText(g.weight, kind: kind)) once more"
        case .start: return "New weight: \(weightText(g.weight, kind: kind))"
        case .building: return "\(g.repsToGo) rep\(g.repsToGo == 1 ? "" : "s") from \(next)"
        }
    }

    static func detail(_ g: Guidance, kind: ExerciseKind) -> String {
        switch g.status {
        case .ready: return "You hit \(g.repHigh)+ on all \(g.sets) sets. Start at \(g.repLow) reps and build back to \(g.repHigh)."
        case .tooEasy: return "Every set went \(g.repHigh + 3)+ reps. If \(weightText(g.nextWeight, kind: kind)) still feels light, jump another step so you land in \(g.repLow)–\(g.repHigh)."
        case .stalled:
            let deload = ((kind == .assisted ? g.weight * 1.1 : g.weight * 0.9) / 5).rounded() * 5
            if abs(deload - g.weight) < 0.01 {
                return "No rep gains in 3 sessions. Try an easier variation or a slower tempo for a week, then build back up."
            }
            return "No rep gains in 3 sessions. Hold \(weightText(g.weight, kind: kind)) once more, or drop to \(weightText(deload, kind: kind)) and build back up."
        case .grind: return "You hit \(g.repHigh) on every set, but above RPE 9. Move up once it feels like RPE 9 or easier."
        case .start: return "Aim for \(g.repLow)+ on every set, then add reps until all \(g.sets) sets hit \(g.repHigh)."
        case .building:
            if let per = g.perSession, let left = g.sessionsLeft {
                let when = g.eta.map { " (around \(Fmt.date($0, "MMMd")))" } ?? ""
                return "At +\(Fmt.num(per, maxDecimals: 1)) reps a session, ready in ~\(left) session\(left == 1 ? "" : "s")\(when)."
            }
            return "Add a rep or two each session until all \(g.sets) sets hit \(g.repHigh)."
        }
    }
}

extension Guidance.Status {
    var tint: Color {
        switch self {
        case .ready, .tooEasy: Palette.orange
        case .stalled, .grind: Palette.yellow
        case .building, .start: Palette.cyan
        }
    }
    var icon: String {
        switch self {
        case .ready, .tooEasy: "arrow.up.circle.fill"
        case .stalled, .grind: "pause.circle.fill"
        case .building, .start: "chart.line.uptrend.xyaxis"
        }
    }
}
