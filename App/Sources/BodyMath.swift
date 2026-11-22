import Foundation

struct TrendPoint: Identifiable, Hashable {
    var id: Date { date }
    var date: Date
    /// Average of that day's weigh-ins.
    var raw: Double
    /// Exponentially smoothed "10-day" trend.
    var trend: Double
}

enum BodyMath {
    /// Daily averages smoothed with a 10% per-day exponential moving average (gaps decay accordingly).
    static func trend(_ samples: [BodySample]) -> [TrendPoint] {
        let cal = Calendar.current
        let byDay = Dictionary(grouping: samples) { cal.startOfDay(for: $0.date) }
        let days = byDay.keys.sorted()
        var out: [TrendPoint] = []
        var t: Double?
        var lastDay: Date?
        for day in days {
            let vals = byDay[day]!.map(\.value)
            let raw = vals.reduce(0, +) / Double(vals.count)
            if let prev = t, let lastDay {
                let gap = max(1, Double(cal.dateComponents([.day], from: lastDay, to: day).day ?? 1))
                let alpha = 1 - pow(0.9, gap)
                t = prev + alpha * (raw - prev)
            } else {
                t = raw
            }
            lastDay = day
            out.append(TrendPoint(date: day, raw: raw, trend: t!))
        }
        return out
    }

    static func trend(at date: Date, _ points: [TrendPoint]) -> Double? {
        points.last { $0.date <= date }?.trend ?? points.first?.trend
    }

    /// Trend change over the last `days` days.
    static func change(_ points: [TrendPoint], days: Int) -> Double? {
        guard let last = points.last, points.count > 1,
              let from = Calendar.current.date(byAdding: .day, value: -days, to: last.date),
              let then = trend(at: from, points) else { return nil }
        return last.trend - then
    }

    /// Change in a slowly-moving series (body fat, lean mass) using first vs last weekly averages within `days`.
    static func seriesChange(_ samples: [BodySample], days: Int) -> Double? {
        let since = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let window = samples.filter { $0.date >= since }.sorted { $0.date < $1.date }
        guard window.count >= 2, let first = window.first?.date, let last = window.last?.date,
              last.timeIntervalSince(first) > 7 * 86400 else { return nil }
        let head = window.filter { $0.date < first.addingTimeInterval(7 * 86400) }.map(\.value)
        let tail = window.filter { $0.date > last.addingTimeInterval(-7 * 86400) }.map(\.value)
        return tail.reduce(0, +) / Double(tail.count) - head.reduce(0, +) / Double(head.count)
    }

    /// Pounds per week, from a least-squares fit of the last 28 days of trend.
    static func ratePerWeek(_ points: [TrendPoint]) -> Double? {
        guard let last = points.last else { return nil }
        let since = last.date.addingTimeInterval(-28 * 86400)
        let window = points.filter { $0.date >= since }
        guard window.count >= 5 else { return nil }
        let xs = window.map { $0.date.timeIntervalSince(since) / 86400 }
        let ys = window.map(\.trend)
        let mx = xs.reduce(0, +) / Double(xs.count), my = ys.reduce(0, +) / Double(ys.count)
        let num = zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) }
        let den = xs.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }
        guard den > 0 else { return nil }
        return num / den * 7
    }

    static func eta(current: Double, goal: Double, ratePerWeek: Double) -> Date? {
        let diff = goal - current
        guard goal > 0, abs(diff) > 0.05, ratePerWeek != 0, diff / ratePerWeek > 0 else { return nil }
        let weeks = diff / ratePerWeek
        guard weeks < 260 else { return nil }
        return Date().addingTimeInterval(weeks * 7 * 86400)
    }
}
