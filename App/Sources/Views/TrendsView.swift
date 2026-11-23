import Charts
import SwiftData
import SwiftUI

struct TrendsView: View {
    @EnvironmentObject var health: HealthStore
    @Query(sort: \Workout.startedAt) private var workouts: [Workout]
    @Query private var exercises: [Exercise]
    @State private var range: ChartRange = .m3
    @State private var drill: StatDrill?
    @ObservedObject private var settings = AppSettings.shared

    private var finished: [Workout] { workouts.filter { $0.endedAt != nil } }

    var body: some View {
        let trend = BodyMath.trend(health.weights)
        Screen {
            HStack(alignment: .bottom) {
                Text("Trends").font(.system(size: 34, weight: .bold))
                Spacer()
                HStack(spacing: 2) {
                    ForEach([ChartRange.m1, .m3, .y1]) { r in
                        Button(r.rawValue) { range = r }
                            .font(.system(size: 13, weight: range == r ? .semibold : .regular))
                            .foregroundStyle(range == r ? .white : Palette.secondary)
                            .frame(width: 38, height: 28).background(range == r ? Palette.fieldHigh : .clear, in: Capsule())
                    }
                }
                .padding(2).background(Palette.card, in: Capsule())
            }
            .padding(.top, 8)
            let saved = settings.savedStatViews.compactMap { s in ExploreConfig.decode(s).map { (s, $0) } }
            if !saved.isEmpty {
                let data = StatsData(workouts: workouts, weights: health.weights)
                ForEach(saved, id: \.0) { json, config in
                    ExploreChartCard(config: config, data: data, onRemove: { settings.savedStatViews.removeAll { $0 == json } }) { drill = $0 }
                }
            }
            if finished.count < 4 {
                NoticeCard(icon: "chart.line.uptrend.xyaxis", tint: Palette.orange, title: "Trends need a couple of weeks",
                           message: "Relative strength and training load show up after a few workouts. Weight vs. lean mass uses Apple Health.")
            } else {
                relativeStrength(trend)
                trainingLoad
            }
            if !trend.isEmpty { weightVsLean(trend) }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $drill) { StatDrillSheet(drill: $0) }
    }

    // MARK: Relative strength
    private func relativeStrength(_ trend: [TrendPoint]) -> some View {
        let start = range.start() ?? .distantPast
        let lifts = exercises.filter { $0.kind == .weightReps }
            .map { ($0, Analytics.sessions($0).filter { $0.bestE1RM > 0 }) }
            .filter { $0.1.count >= 2 }
            .sorted { a, b in
                let pa = Self.bigLifts.firstIndex(of: a.0.name) ?? 99, pb = Self.bigLifts.firstIndex(of: b.0.name) ?? 99
                return pa != pb ? pa < pb : a.1.count > b.1.count
            }
            .prefix(3)
        return Card {
            Text("Relative strength").font(.system(size: 17, weight: .semibold))
            Text("Estimated 1RM ÷ trend bodyweight").font(.system(size: 13)).foregroundStyle(Palette.secondary)
            if trend.isEmpty {
                Text("Needs weigh-ins from Apple Health or manual entry.").font(.system(size: 15)).foregroundStyle(Palette.secondary).padding(.top, 10)
            }
            ForEach(Array(lifts.enumerated()), id: \.element.0.persistentModelID) { i, item in
                let ratios = item.1.compactMap { s -> (Date, Double)? in
                    guard let bw = BodyMath.trend(at: s.date, trend) ?? trend.first?.trend, bw > 0 else { return nil }
                    return (s.date, s.bestE1RM / bw)
                }
                let shown = ratios.filter { $0.0 >= start }
                if let last = shown.last ?? ratios.last {
                    if i > 0 { RowDivider() }
                    HStack {
                        Text(item.0.name).font(.system(size: 17))
                        Spacer()
                        Sparkline(values: runningMax(shown.map(\.1)), tint: Palette.orange, lineWidth: 1.5).frame(width: 70, height: 22)
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(String(format: "%.2f×", last.1)).font(.system(size: 17, weight: .bold)).monospacedDigit()
                            if let first = shown.first {
                                Text(String(format: "%@%.2f", last.1 >= first.1 ? "+" : "−", abs(last.1 - first.1)))
                                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.orange)
                            }
                        }
                        .frame(width: 64, alignment: .trailing)
                    }
                    .padding(.vertical, 10)
                }
            }
        }
    }

    static let bigLifts = ["Bench Press", "Back Squat", "Deadlift", "Overhead Press"]

    private func runningMax(_ v: [Double]) -> [Double] {
        var m = -Double.infinity
        return v.map { m = max(m, $0); return m }
    }

    // MARK: Training load
    private var trainingLoad: some View {
        let start = Analytics.weekStart()
        let weeks: [(Date, Double, Double)] = (0..<8).reversed().map { w in
            let s = Calendar.current.date(byAdding: .day, value: -7 * w, to: start)!
            let e = Calendar.current.date(byAdding: .day, value: 7, to: s)!
            let lift = finished.filter { $0.startedAt >= s && $0.startedAt < e }.reduce(0) { $0 + $1.duration / 60 }
            let run = health.runs.filter { $0.start >= s && $0.start < e }.reduce(0) { $0 + $1.duration / 60 }
            return (s, lift, run)
        }
        return Card {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Weekly training load").font(.system(size: 17, weight: .semibold))
                    Text("Minutes per week, last 8 weeks").font(.system(size: 13)).foregroundStyle(Palette.secondary)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 3) {
                    legend("Lifting", Palette.orange)
                    legend("Running", Palette.cyan)
                }
            }
            Chart {
                ForEach(Array(weeks.enumerated()), id: \.offset) { i, w in
                    let current = i == weeks.count - 1
                    BarMark(x: .value("Week", w.0, unit: .weekOfYear), y: .value("Minutes", w.1))
                        .foregroundStyle(Palette.orange.opacity(current ? 0.55 : 1))
                    BarMark(x: .value("Week", w.0, unit: .weekOfYear), y: .value("Minutes", w.2))
                        .foregroundStyle(Palette.cyan.opacity(current ? 0.55 : 1))
                }
            }
            .chartXAxis {
                AxisMarks(values: [weeks[0].0, weeks[4].0, weeks[7].0]) { v in
                    AxisValueLabel { if let d = v.as(Date.self) { Text(d == weeks[7].0 ? "This wk" : Fmt.date(d, "MMM d")) } }
                }
            }
            .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { AxisGridLine().foregroundStyle(Palette.separator); AxisValueLabel() } }
            .frame(height: 190).padding(.top, 12)
        }
    }

    private func legend(_ t: String, _ c: Color) -> some View {
        HStack(spacing: 5) { RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 9, height: 9); Text(t) }
            .font(.system(size: 12)).foregroundStyle(Palette.secondary)
    }

    // MARK: Weight vs lean
    private func weightVsLean(_ trend: [TrendPoint]) -> some View {
        let w = BodyMath.change(trend, days: 90)
        let l = BodyMath.seriesChange(health.lean, days: 90)
        let now = Date()
        let cal = Calendar.current
        func vol(_ a: Date, _ b: Date) -> Double { finished.filter { $0.startedAt >= a && $0.startedAt < b }.reduce(0) { $0 + $1.volume } }
        let recent = vol(cal.date(byAdding: .day, value: -45, to: now)!, now)
        let prior = vol(cal.date(byAdding: .day, value: -90, to: now)!, cal.date(byAdding: .day, value: -45, to: now)!)
        let volChange = prior > 0 ? (recent - prior) / prior : nil
        let verdict: String = {
            guard let w, let l else { return "Needs body-composition readings from your scale to compare." }
            if w < -0.5 && l >= -0.5 { return "Losing fat while keeping muscle." }
            if w < -0.5 { return "Losing weight, and some lean mass with it. Keep protein and training volume up." }
            if w > 0.5 && l > 0.5 { return "Gaining, with lean mass going up too." }
            return "Weight is holding steady."
        }()
        return Card {
            Text("Weight vs. lean mass, 90 days").font(.system(size: 17, weight: .semibold))
            HStack(spacing: 8) {
                box("Weight", w.map { "\(Fmt.signed(Units.display($0))) \(Units.unitLabel)" } ?? "–", Palette.cyan)
                box("Lean mass", l.map { "\(Fmt.signed(Units.display($0))) \(Units.unitLabel)" } ?? "–", Palette.cyan)
                box("Lift volume", volChange.map { "\($0 >= 0 ? "+" : "−")\(Int(abs($0 * 100).rounded()))%" } ?? "–", Palette.orange)
            }
            .padding(.top, 12)
            Text("\(verdict) Scale body-composition readings swing day to day, so this compares 90-day trends.")
                .font(.system(size: 13)).foregroundStyle(Palette.secondary).padding(.top, 12).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func box(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 12)).foregroundStyle(Palette.secondary)
            Text(value).font(.system(size: 20, weight: .bold)).foregroundStyle(color).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.field, in: RoundedRectangle(cornerRadius: 10))
    }
}
