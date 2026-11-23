import Foundation
import SwiftData
import UserNotifications

/// "Your year in training": unlocks Dec 1 with a notification and a Today card, then lives in Settings › Your year.
struct WrappedData {
    struct Jump {
        let name: String
        let from: Double
        let to: Double
        let isReps: Bool
        var delta: Double { to - from }
    }

    let year: Int
    var volume: Double = 0
    var sessions = 0
    var groups: [(String, Double)] = []
    var prCount = 0
    var bestPRMonth: (String, Int)?
    var jumps: [Jump] = []
    var bodyweightJump: Jump?
    var runMeters: Double = 0
    var runCount = 0
    var topWeekday: String?
    var earliest: Date?
    var streakWeeks = 0
    var bestMonth: String?
    var weightFrom: Double?
    var weightTo: Double?
    var ratioFrom: Double?
    var ratioTo: Double?
    var firstPhoto: ProgressPhoto?
    var lastPhoto: ProgressPhoto?

    @MainActor
    init(year: Int, workouts: [Workout], photos: [ProgressPhoto], now: Date = Date()) {
        self.year = year
        let health = HealthStore.shared
        let cal = Calendar.current
        let start = cal.date(from: DateComponents(year: year, month: 1, day: 1))!
        let end = cal.date(from: DateComponents(year: year + 1, month: 1, day: 1))!
        let data = StatsData(workouts: workouts, weights: health.weights)
        let sets = data.sets(from: start, to: end)
        let ws = data.workouts(from: start, to: end)
        volume = sets.reduce(0) { $0 + $1.volume }
        sessions = ws.count

        var byGroup: [String: Double] = [:]
        for s in sets where s.volume > 0 {
            let g = s.primary?.group ?? .core
            byGroup[g == .shouldersArms ? "Shoulders, arms" : g.rawValue, default: 0] += s.volume
        }
        groups = byGroup.sorted { $0.value > $1.value }.prefix(4).map { ($0.key, volume > 0 ? $0.value / volume : 0) }

        var prMonths: [Int: Int] = [:]
        for w in ws {
            for e in w.entries where Analytics.bestPR(e) != nil {
                prCount += 1
                prMonths[cal.component(.month, from: w.startedAt), default: 0] += 1
            }
        }
        if let best = prMonths.max(by: { $0.value < $1.value }), prCount > 1 {
            bestPRMonth = (cal.monthSymbols[best.key - 1], best.value)
        }

        var weightJumps: [Jump] = []
        var repJumps: [Jump] = []
        for ex in Set(sets.map(\.exercise)) {
            let ss = Analytics.sessions(ex).filter { $0.date >= start && $0.date < end }
            guard ss.count >= 2, let first = ss.first else { continue }
            switch ex.kind {
            case .weightReps:
                let to = ss.map(\.bestE1RM).max() ?? 0
                if first.bestE1RM > 0, to > first.bestE1RM { weightJumps.append(Jump(name: ex.name, from: first.bestE1RM, to: to, isReps: false)) }
            case .bodyweight:
                let to = ss.map(\.maxReps).max() ?? 0
                if to > first.maxReps { repJumps.append(Jump(name: ex.name, from: Double(first.maxReps), to: Double(to), isReps: true)) }
            default: break
            }
        }
        jumps = Array(weightJumps.sorted { $0.delta > $1.delta }.prefix(3))
        bodyweightJump = repJumps.max { $0.delta < $1.delta }

        let runs = health.runs.filter { $0.start >= start && $0.start < end }
        runMeters = runs.reduce(0) { $0 + $1.meters }
        runCount = runs.count

        let starts = ws.map(\.startedAt) + runs.map(\.start)
        let dayCounts = Dictionary(grouping: starts) { cal.component(.weekday, from: $0) }.mapValues(\.count)
        if let top = dayCounts.max(by: { $0.value < $1.value }) { topWeekday = cal.weekdaySymbols[top.key - 1] }
        let monthCounts = Dictionary(grouping: starts) { cal.component(.month, from: $0) }.mapValues(\.count)
        if let top = monthCounts.max(by: { $0.value < $1.value }) { bestMonth = cal.monthSymbols[top.key - 1] }
        if let m = starts.map({ cal.component(.hour, from: $0) * 60 + cal.component(.minute, from: $0) }).min() {
            earliest = cal.startOfDay(for: now).addingTimeInterval(Double(m) * 60)
        }

        let goal = max(1, AppSettings.shared.weeklyLiftGoal)
        var week = Analytics.weekStart(start)
        var run = 0
        while week < min(end, now) {
            let next = cal.date(byAdding: .day, value: 7, to: week)!
            if ws.filter({ $0.startedAt >= week && $0.startedAt < next }).count >= goal { run += 1; streakWeeks = max(streakWeeks, run) } else { run = 0 }
            week = next
        }

        let trend = BodyMath.trend(health.weights).filter { $0.date >= start && $0.date < end }
        if trend.count >= 2 { weightFrom = trend.first?.trend; weightTo = trend.last?.trend }
        let allTrend = BodyMath.trend(health.weights)
        if let bench = sets.first(where: { $0.exercise.name == "Bench Press" })?.exercise {
            let ss = Analytics.sessions(bench).filter { $0.date >= start && $0.date < end && $0.bestE1RM > 0 }
            func ratio(_ s: Session?) -> Double? {
                guard let s, let bw = BodyMath.trend(at: s.date, allTrend), bw > 0 else { return nil }
                return s.bestE1RM / bw
            }
            if ss.count >= 2 { ratioFrom = ratio(ss.first); ratioTo = ratio(ss.suffix(3).max { $0.bestE1RM < $1.bestE1RM }) }
        }

        let front = photos.filter { $0.pose == .front && $0.date >= start && $0.date < end }.sorted { $0.date < $1.date }
        if front.count >= 2 { firstPhoto = front.first; lastPhoto = front.last }
    }

    var hasData: Bool { sessions > 0 || runCount > 0 }

    static func volumeFact(_ pounds: Double) -> String? {
        let things: [(Double, String, String)] = [
            (330_000, "blue whale", "blue whales"), (13_000, "African elephant", "African elephants"),
            (4_000, "car", "cars"), (1_000, "grand piano", "grand pianos"),
        ]
        for t in things {
            let n = Int((pounds / t.0).rounded())
            if pounds / t.0 >= 1.5 { return "That's about the weight of \(word(n)) \(n == 1 ? t.1 : t.2)." }
        }
        return nil
    }

    static func runFact(_ meters: Double) -> String? {
        let miles = meters / 1609.344
        if miles >= 383 { return "That's farther than driving from San Francisco to LA." }
        if miles >= 215 { return "That's farther than driving from New York to Boston." }
        if miles >= 52.4 { return "That's \(word(Int(miles / 26.2))) marathons' worth." }
        if miles >= 26.2 { return "That's more than a marathon." }
        return nil
    }

    static func word(_ n: Int) -> String {
        let words = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve"]
        return n < words.count ? words[n] : "\(n)"
    }

    static func big(_ v: Double) -> (String, String) {
        if v >= 1_000_000 { return (Fmt.num(v / 1_000_000, maxDecimals: 1), "M") }
        if v >= 10_000 { return ("\(Int((v / 1000).rounded()))", "k") }
        return (Fmt.num(v, maxDecimals: 0), "")
    }
}

enum Wrapped {
    static var currentYear: Int { Calendar.current.component(.year, from: Date()) }

    static func unlockDate(_ year: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: 12, day: 1, hour: 9))!
    }

    static func isUnlocked(_ year: Int, now: Date = Date()) -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-wrappedUnlocked") { return true }
        #endif
        return now >= Calendar.current.startOfDay(for: unlockDate(year))
    }

    /// The year shown in Settings › Your year: this year once unlocked, otherwise last year.
    static var latestYear: Int { isUnlocked(currentYear) ? currentYear : currentYear - 1 }

    /// Today shows a card for the whole of December until you watch it.
    static var showTodayCard: Bool {
        let now = Date()
        return isUnlocked(currentYear, now: now) && Calendar.current.component(.month, from: now) == 12
            && AppSettings.shared.wrappedSeenYear < currentYear
    }

    static func scheduleNotification() {
        let year = currentYear
        guard !isUnlocked(year) else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { s in
            guard s.authorizationStatus == .authorized || s.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = "Your \(year) in training is ready"
            content.body = "Volume, PRs, miles and how you showed up this year."
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: unlockDate(year))
            center.add(UNNotificationRequest(identifier: "wrapped-\(year)", content: content,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }
    }
}
