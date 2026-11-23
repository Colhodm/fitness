import Charts
import SwiftData
import SwiftUI

// MARK: - Data

/// One logged working set, with the load used for volume.
struct StatSet: Identifiable {
    let record: SetRecord
    let exercise: Exercise
    let workout: Workout
    /// Pounds per rep. Bodyweight exercises add trend bodyweight; assisted ones subtract the assist.
    let load: Double
    var id: PersistentIdentifier { record.persistentModelID }
    var date: Date { workout.startedAt }
    var reps: Int { record.reps }
    var volume: Double { load * Double(record.reps) }
    var e1RM: Double { exercise.kind == .weightReps && record.reps <= 10 ? Analytics.e1RM(record.weight, record.reps) : 0 }
    var primary: Muscle? { exercise.muscles.first.map { $0 == .legs ? .quads : $0 } }
    /// Hard-set credit: primary muscle 1 set, secondary muscles half a set.
    var muscleCredit: [(Muscle, Double)] {
        exercise.muscles.enumerated().map { i, m in (m == .legs ? .quads : m, i == 0 ? 1 : 0.5) }
    }
}

struct StatsData {
    let sets: [StatSet]
    let workouts: [Workout]

    init(workouts all: [Workout], weights: [BodySample]) {
        let trend = BodyMath.trend(weights)
        var out: [StatSet] = []
        var trained: [Workout] = []
        for w in all where w.endedAt != nil {
            var any = false
            for e in w.entries {
                guard let ex = e.exercise else { continue }
                let bw = ex.kind == .bodyweight || ex.kind == .assisted ? (BodyMath.trend(at: w.startedAt, trend) ?? 0) : 0
                for s in e.doneWorkingSets {
                    let load: Double
                    switch ex.kind {
                    case .weightReps: load = s.weight
                    case .bodyweight: load = bw + s.weight
                    case .assisted: load = max(0, bw - s.weight)
                    case .timed, .distanceWeight: load = 0
                    }
                    out.append(StatSet(record: s, exercise: ex, workout: w, load: load))
                    any = true
                }
            }
            if any { trained.append(w) }
        }
        sets = out.sorted { $0.date < $1.date }
        workouts = trained.sorted { $0.startedAt < $1.startedAt }
    }

    func sets(from a: Date, to b: Date = .distantFuture) -> [StatSet] { sets.filter { $0.date >= a && $0.date < b } }
    func workouts(from a: Date, to b: Date = .distantFuture) -> [Workout] { workouts.filter { $0.startedAt >= a && $0.startedAt < b } }
}

enum StatsRange: Int, CaseIterable, Identifiable {
    case thisWeek = 1, w4 = 4, w8 = 8, w12 = 12, m6 = 26, y1 = 52
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .thisWeek: "This week"
        case .m6: "Last 6 months"
        case .y1: "Last year"
        default: "Last \(rawValue) weeks"
        }
    }
    var start: Date { Stats.start(weeks: rawValue) }
}

enum RepRange: Int, CaseIterable, Identifiable {
    case low, mid, high, veryHigh
    var id: Int { rawValue }
    init?(reps: Int) {
        switch reps {
        case ..<1: return nil
        case 1...5: self = .low
        case 6...8: self = .mid
        case 9...12: self = .high
        default: self = .veryHigh
        }
    }
    var title: String { ["1–5 reps", "6–8 reps", "9–12 reps", "13+ reps"][rawValue] }
}

enum Stats {
    static let colors: [Color] = [Palette.orange, Color(hex: 0x7D7AFF), Color(hex: 0x30D158), Color(hex: 0xBF5AF2), Palette.yellow, Palette.cyan]

    /// Monday of the week `weeks - 1` weeks before this one.
    static func start(weeks: Int, now: Date = Date()) -> Date {
        Calendar.mondayFirst.date(byAdding: .weekOfYear, value: -(max(1, weeks) - 1), to: Analytics.weekStart(now))!
    }

    static func compact(_ v: Double) -> String {
        if v >= 100_000 { return "\(Int((v / 1000).rounded()))k" }
        if v >= 10_000 { return "\(Fmt.num(v / 1000, maxDecimals: 1))k" }
        return Fmt.num(v, maxDecimals: 0)
    }

    static func percent(_ v: Double) -> String { "\(v >= 0 ? "+" : "−")\(Int(abs(v * 100).rounded()))%" }

    static func ratio(_ a: Double, _ b: Double) -> Double? { b > 0 ? a / b : nil }

    static func median(_ v: [Double]) -> Double? {
        guard !v.isEmpty else { return nil }
        let s = v.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }

    /// Monday = 0
    static func weekdayIndex(_ d: Date) -> Int { (Calendar.current.component(.weekday, from: d) + 5) % 7 }

    static func equipmentColor(_ e: Equipment) -> Color {
        switch e {
        case .barbell: Palette.orange
        case .dumbbell: Color(hex: 0x7D7AFF)
        case .cable: Color(hex: 0x30D158)
        case .machine: Color(hex: 0xBF5AF2)
        case .kettlebell: Palette.yellow
        case .bodyweight: Palette.cyan
        case .other: Palette.tertiary
        }
    }
}

struct StatDrill: Identifiable {
    let id = UUID()
    let title: String
    let sets: [StatSet]
}

// MARK: - Screen

enum StatsTab: String, CaseIterable {
    case explore = "Explore", muscles = "Muscles", lifts = "Lifts", habits = "Habits", effort = "Effort"
}

struct LiftStatsView: View {
    @EnvironmentObject var health: HealthStore
    @Query(sort: \Workout.startedAt) private var workouts: [Workout]
    @State private var tab: StatsTab = Self.launchArg("-statsTab").flatMap(StatsTab.init) ?? .explore
    @State private var range: StatsRange = Self.launchArg("-statsWeeks").flatMap(Int.init).flatMap(StatsRange.init) ?? .w8
    @State private var explore = ExploreConfig()
    @State private var drill: StatDrill?

    var body: some View {
        let data = StatsData(workouts: workouts, weights: health.weights)
        Screen {
            Text("Lift stats").font(.system(size: 34, weight: .bold))
            SegmentedPicker(options: StatsTab.allCases.map { ($0, $0.rawValue) }, selection: $tab)
            if data.sets.isEmpty {
                NoticeCard(icon: "chart.bar.xaxis", tint: Palette.orange, title: "No lifts yet",
                           message: "Finish a workout, log a past one, or import from Notes, and your stats show up here.")
            } else {
                switch tab {
                case .explore: ExploreTab(config: $explore, data: data) { drill = $0 }
                case .muscles: MusclesTab(data: data, range: range) { drill = $0 }
                case .lifts: LiftsTab(data: data, range: range) { drill = $0 }
                case .habits: HabitsTab(data: data, range: range) { drill = $0 }
                case .effort: EffortTab(data: data, range: range) { drill = $0 }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Range", selection: $range) {
                        ForEach(StatsRange.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(range.title)
                        Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
                    }
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                }
            }
        }
        .onChange(of: range, initial: true) { _, r in explore.weeks = r.rawValue }

        .sheet(item: $drill) { StatDrillSheet(drill: $0) }
    }

    /// DEBUG launch arguments for Simulator screenshots.
    private static func launchArg(_ key: String) -> String? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: key), i + 1 < args.count { return args[i + 1] }
        #endif
        return nil
    }
}

// MARK: - Explore

enum StatMetric: String, CaseIterable, Codable {
    case volume = "Volume", sets = "Sets", reps = "Reps", e1RM = "Est. 1RM"
    var lower: String { self == .e1RM ? "est. 1RM" : rawValue.lowercased() }
}

enum StatDimension: String, CaseIterable, Codable {
    case muscle = "Muscle group", exercise = "Exercise", routine = "Routine", equipment = "Equipment", repRange = "Rep range"
}

enum StatPeriod: String, CaseIterable, Codable {
    case week = "Week", month = "Month"
}

struct ExploreConfig: Codable, Equatable {
    var metric: StatMetric = .volume
    var by: StatDimension = .muscle
    var per: StatPeriod = .week
    /// Exercise name, nil = all exercises.
    var exercise: String?
    var weeks: Int = 8

    var title: String {
        let unit = metric == .volume ? ", \(Units.unitLabel)" : ""
        return "\(per == .week ? "Weekly" : "Monthly") \(metric.lower)\(unit)\(exercise.map { " · \($0)" } ?? "")"
    }

    var json: String {
        let enc = JSONEncoder()
        enc.outputFormatting = .sortedKeys
        return (try? enc.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    static func decode(_ s: String) -> ExploreConfig? { try? JSONDecoder().decode(ExploreConfig.self, from: Data(s.utf8)) }

    func key(_ s: StatSet) -> String {
        switch by {
        case .muscle: s.primary?.group.rawValue ?? "Other"
        case .exercise: s.exercise.name
        case .routine: s.workout.routine?.name ?? "No routine"
        case .equipment: s.exercise.equipment.title
        case .repRange: RepRange(reps: s.reps)?.title ?? "Timed and carries"
        }
    }

    func value(_ sets: [StatSet]) -> Double {
        switch metric {
        case .volume: sets.reduce(0) { $0 + $1.volume }
        case .sets: Double(sets.count)
        case .reps: Double(sets.reduce(0) { $0 + $1.reps })
        case .e1RM: sets.map(\.e1RM).max() ?? 0
        }
    }

    func display(_ v: Double) -> Double { metric == .volume || metric == .e1RM ? Units.display(v) : v }

    func format(_ v: Double) -> String {
        switch metric {
        case .volume: "\(Stats.compact(Units.display(v))) \(Units.unitLabel)"
        case .e1RM: Fmt.wu(v.rounded())
        case .sets, .reps: Stats.compact(v)
        }
    }

    func periodStart(_ d: Date) -> Date {
        per == .week ? Analytics.weekStart(d) : Calendar.current.dateInterval(of: .month, for: d)!.start
    }
}

struct ExploreTab: View {
    @Binding var config: ExploreConfig
    let data: StatsData
    let onDrill: (StatDrill) -> Void
    @ObservedObject private var settings = AppSettings.shared

    private var exerciseNames: [String] {
        let counts = Dictionary(grouping: data.sets, by: \.exercise.name).mapValues(\.count)
        return counts.keys.sorted { counts[$0]! == counts[$1]! ? $0 < $1 : counts[$0]! > counts[$1]! }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        word("Show")
                        menu(config.metric.rawValue, StatMetric.allCases.map { m in (m.rawValue, { config.metric = m }) })
                        word("by")
                        menu(config.by.rawValue, StatDimension.allCases.map { d in (d.rawValue, { config.by = d }) })
                    }
                    HStack(spacing: 8) {
                        word("per")
                        menu(config.per.rawValue, StatPeriod.allCases.map { p in (p.rawValue, { config.per = p }) })
                        word("for")
                        menu(config.exercise ?? "All exercises",
                             [("All exercises", { config.exercise = nil })] + exerciseNames.map { n in (n, { config.exercise = n }) })
                    }
                    Text("Tap a bar or row to see the sets behind it.").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                }
            }
            let saved = settings.savedStatViews.contains(config.json)
            ExploreChartCard(config: config, data: data, saved: saved, showTable: true,
                             onSave: { if !saved { settings.savedStatViews.append(config.json) } }, onDrill: onDrill)
        }
    }

    private func word(_ t: String) -> some View { Text(t).font(.system(size: 17)).foregroundStyle(Palette.secondary) }

    private func menu(_ title: String, _ items: [(String, () -> Void)]) -> some View {
        Menu {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in Button(item.0, action: item.1) }
        } label: {
            HStack(spacing: 4) {
                Text(title).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
            }
            .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.orange)
            .padding(.horizontal, 10).frame(height: 32)
            .background(Palette.orange.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct ExploreChartCard: View {
    let config: ExploreConfig
    let data: StatsData
    var saved = false
    var showTable = false
    var onSave: (() -> Void)?
    var onRemove: (() -> Void)?
    let onDrill: (StatDrill) -> Void

    private struct Point: Identifiable {
        let id = UUID()
        let date: Date
        let key: String
        let value: Double
    }

    var body: some View {
        let now = Date()
        let start = Stats.start(weeks: config.weeks)
        let priorStart = Calendar.mondayFirst.date(byAdding: .weekOfYear, value: -config.weeks, to: start)!
        let filtered = data.sets.filter { config.exercise == nil || $0.exercise.name == config.exercise }
        let shown = filtered.filter { $0.date >= start }
        let prior = filtered.filter { $0.date >= priorStart && $0.date < start }
        // Only compare with the prior period when history covers most of it.
        let comparable = (data.sets.first?.date ?? .distantFuture) <= priorStart.addingTimeInterval(Double(config.weeks) * 7 * 86400 / 4)
        let groups = Dictionary(grouping: shown) { config.key($0) }
        let priorGroups = Dictionary(grouping: prior) { config.key($0) }
        let ranked = groups.map { ($0.key, config.value($0.value)) }.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
        let top = Array(ranked.prefix(4).map(\.0))
        let hasOther = config.metric != .e1RM && ranked.count > 4
        let seriesNames = top + (hasOther ? ["Other"] : [])
        let periods = periodStarts(from: start, to: now)
        let unit: Calendar.Component = config.per == .week ? .weekOfYear : .month
        let points = periods.enumerated().flatMap { i, p -> [Point] in
            let end = i + 1 < periods.count ? periods[i + 1] : .distantFuture
            let inPeriod = shown.filter { $0.date >= p && $0.date < end }
            return seriesNames.compactMap { name in
                let sets = inPeriod.filter { name == "Other" ? !top.contains(config.key($0)) : config.key($0) == name }
                let v = config.value(sets)
                return v > 0 ? Point(date: p, key: name, value: config.display(v)) : nil
            }
        }
        Card {
            HStack(alignment: .firstTextBaseline) {
                Text(config.title).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                Spacer()
                if let onSave {
                    Button(saved ? "Saved" : "Save view", action: onSave)
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(saved ? Palette.secondary : Palette.orange)
                        .padding(.horizontal, 10).frame(height: 26)
                        .background(Palette.orange.opacity(saved ? 0 : 0.16), in: Capsule())
                        .disabled(saved)
                }
                if let onRemove {
                    Menu {
                        Button("Remove from Trends", role: .destructive, action: onRemove)
                    } label: {
                        Image(systemName: "ellipsis").foregroundStyle(Palette.secondary).frame(width: 28, height: 26)
                    }
                }
            }
            if points.isEmpty {
                Text("No sets in this range.").font(.system(size: 15)).foregroundStyle(Palette.secondary).padding(.vertical, 24)
            } else {
                Chart(points) { p in
                    if config.metric == .e1RM {
                        LineMark(x: .value("Period", p.date, unit: unit), y: .value("Value", p.value))
                            .foregroundStyle(by: .value("Group", p.key))
                            .symbol(by: .value("Group", p.key))
                    } else {
                        BarMark(x: .value("Period", p.date, unit: unit), y: .value("Value", p.value))
                            .foregroundStyle(by: .value("Group", p.key))
                    }
                }
                .chartForegroundStyleScale(domain: seriesNames, range: seriesNames.indices.map { color($0, seriesNames) })
                .chartLegend(.hidden)
                .chartXAxis {
                    AxisMarks(values: axisDates(periods)) { v in
                        let d = v.as(Date.self)
                        AxisValueLabel(anchor: d == periods.last && periods.count > 1 ? .topTrailing : .top) {
                            if let d { Text(axisLabel(d, last: periods.last)) }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { v in
                        AxisGridLine().foregroundStyle(Palette.separator)
                        AxisValueLabel { if let d = v.as(Double.self) { Text(Stats.compact(d)) } }
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { g in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .onTapGesture { loc in
                                let x = loc.x - (proxy.plotFrame.map { g[$0].origin.x } ?? 0)
                                guard let d: Date = proxy.value(atX: x), let i = periods.lastIndex(where: { $0 <= d }) else { return }
                                let end = i + 1 < periods.count ? periods[i + 1] : .distantFuture
                                let title = config.per == .week ? "Week of \(Fmt.date(periods[i], "MMM d"))" : Fmt.date(periods[i], "MMMM yyyy")
                                onDrill(StatDrill(title: title, sets: shown.filter { $0.date >= periods[i] && $0.date < end }))
                            }
                    }
                }
                .frame(height: 170).padding(.top, 12)
            }
            if showTable && !ranked.isEmpty {
                HStack {
                    Text(config.by.rawValue.uppercased()).frame(maxWidth: .infinity, alignment: .leading)
                    Text(config.weeks == 1 ? "THIS WEEK" : "\(config.weeks) WEEKS").frame(width: 90, alignment: .trailing)
                    Text("VS PRIOR").frame(width: 70, alignment: .trailing)
                }
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.secondary)
                .padding(.top, 16).padding(.bottom, 6)
                ForEach(Array(ranked.prefix(12).enumerated()), id: \.offset) { i, row in
                    RowDivider()
                    let pv = config.value(priorGroups[row.0] ?? [])
                    Button {
                        onDrill(StatDrill(title: row.0, sets: groups[row.0] ?? []))
                    } label: {
                        HStack {
                            Circle().fill(top.contains(row.0) ? color(top.firstIndex(of: row.0)!, seriesNames) : Palette.tertiary).frame(width: 8, height: 8)
                            Text(row.0).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            Text(config.format(row.1)).monospacedDigit().frame(width: 90, alignment: .trailing)
                            Text(!comparable ? "–" : (pv > 0 ? Stats.percent((row.1 - pv) / pv) : "New"))
                                .foregroundStyle(comparable && row.1 >= pv ? Palette.orange : Palette.secondary)
                                .monospacedDigit().frame(width: 70, alignment: .trailing)
                        }
                        .font(.system(size: 15)).frame(height: 40).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func color(_ i: Int, _ names: [String]) -> Color {
        names[i] == "Other" ? Palette.tertiary : Stats.colors[i % Stats.colors.count]
    }

    private func periodStarts(from start: Date, to now: Date) -> [Date] {
        let unit: Calendar.Component = config.per == .week ? .weekOfYear : .month
        var out: [Date] = []
        var p = config.periodStart(start)
        while p <= now {
            out.append(p)
            p = Calendar.mondayFirst.date(byAdding: unit, value: 1, to: p)!
        }
        return out
    }

    private func axisDates(_ p: [Date]) -> [Date] {
        guard let first = p.first, let last = p.last else { return [] }
        return p.count < 3 ? p : [first, p[p.count / 2], last]
    }

    private func axisLabel(_ d: Date, last: Date?) -> String {
        if config.per == .week { return d == last ? "This wk" : Fmt.date(d, "MMM d") }
        return Fmt.date(d, "MMM")
    }
}

// MARK: - Muscles

struct MusclesTab: View {
    let data: StatsData
    let range: StatsRange
    let onDrill: (StatDrill) -> Void

    private static func credit(_ sets: [StatSet]) -> [Muscle: Double] {
        var credit: [Muscle: Double] = [:]
        for s in sets { for (m, c) in s.muscleCredit { credit[m, default: 0] += c } }
        return credit
    }

    private static let base: [Muscle] = [.back, .chest, .quads, .shoulders, .triceps, .glutes, .biceps, .hamstrings, .core]

    var body: some View {
        let sets = data.sets(from: range.start)
        let credit = Self.credit(sets)
        let weeks = Double(range.rawValue)
        let muscles = Self.base + ((credit[.calves] ?? 0) > 0 ? [.calves] : [])
        let rows = muscles.map { ($0, (credit[$0] ?? 0) / weeks) }.sorted { $0.1 > $1.1 }
        let under = rows.filter { $0.1 < 10 }.count
        let scale = max(22, (rows.first?.1 ?? 0) * 1.1)
        VStack(alignment: .leading, spacing: 16) {
            Card {
                Text("Hard sets per muscle").font(.system(size: 17, weight: .semibold))
                Text(under == 0 ? "Every group is at or above your target of 10–20 a week"
                     : "\(under) group\(under == 1 ? " is" : "s are") under your target of 10–20 a week")
                    .font(.system(size: 13)).foregroundStyle(Palette.secondary).padding(.bottom, 12)
                ForEach(rows, id: \.0) { m, v in
                    Button {
                        onDrill(StatDrill(title: m.title, sets: sets.filter { s in s.muscleCredit.contains { $0.0 == m } }))
                    } label: {
                        HStack(spacing: 8) {
                            Text(m.title).font(.system(size: 15)).frame(width: 96, alignment: .leading)
                            GeometryReader { g in
                                let w = g.size.width
                                ZStack(alignment: .leading) {
                                    Rectangle().fill(Palette.field.opacity(0.6))
                                        .frame(width: w * 10 / scale).offset(x: w * 10 / scale)
                                    RoundedRectangle(cornerRadius: 3).fill(v >= 10 ? Palette.orange : Palette.fieldHigh)
                                        .frame(width: max(2, w * v / scale), height: 14)
                                    Text(Fmt.num(v, maxDecimals: 1)).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                                        .offset(x: w * v / scale + 6)
                                }
                                .frame(maxHeight: .infinity)
                            }
                            .frame(height: 22)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                HStack(spacing: 8) {
                    Color.clear.frame(width: 96, height: 1)
                    GeometryReader { g in
                        ForEach([0.0, 10, 20], id: \.self) { t in
                            Text(Fmt.num(t)).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                                .position(x: g.size.width * t / scale, y: 6)
                        }
                    }
                    .frame(height: 12)
                }
                .padding(.top, 4)
                HStack(spacing: 12) {
                    legend("In target", Palette.orange)
                    legend("Below target", Palette.fieldHigh)
                }
                .padding(.top, 10)
                Text("Secondary muscles count as half a set\(range == .thisWeek ? "" : " · averaged per week")")
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary).padding(.top, 2)
            }
            balance
        }
    }

    private var balance: some View {
        let sets = data.sets(from: StatsRange.w4.start)
        let push = sets.filter { [.chest, .shoulders, .triceps].contains($0.primary) }
        let pull = sets.filter { [.back, .biceps].contains($0.primary) }
        let upper = sets.filter { $0.primary?.isUpper == true }
        let lower = sets.filter { $0.primary?.isLower == true }
        func credit(_ m: Muscle) -> Double { sets.reduce(0) { t, s in t + s.muscleCredit.filter { $0.0 == m }.reduce(0) { $0 + $1.1 } } }
        let rows: [(String, Double?, (Double) -> String, [StatSet])] = [
            ("Push to pull volume", Stats.ratio(push.reduce(0) { $0 + $1.volume }, pull.reduce(0) { $0 + $1.volume }),
             { $0 > 1.25 ? "Push-heavy" : ($0 < 0.8 ? "Pull-heavy" : "Even") }, push + pull),
            ("Upper to lower sets", Stats.ratio(Double(upper.count), Double(lower.count)),
             { $0 > 1.5 ? "Upper-heavy" : ($0 < 0.67 ? "Lower-heavy" : "Even") }, upper + lower),
            ("Hamstrings to quads sets", Stats.ratio(credit(.hamstrings), credit(.quads)),
             { $0 < 0.75 ? "Low" : ($0 > 1.33 ? "High" : "Even") },
             sets.filter { s in s.muscleCredit.contains { $0.0 == .hamstrings || $0.0 == .quads } }),
        ]
        return Card {
            CardTitle(title: "Balance", trailing: "Last 4 weeks")
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                RowDivider().padding(.top, i == 0 ? 10 : 0)
                Button { onDrill(StatDrill(title: row.0, sets: row.3)) } label: {
                    HStack {
                        Text(row.0).font(.system(size: 15)).frame(maxWidth: .infinity, alignment: .leading)
                        Text(row.1.map { "\(Fmt.fixed($0, $0 >= 10 ? 0 : ($0 >= 1 ? 1 : 2))) : 1" } ?? "–")
                            .font(.system(size: 15, weight: .semibold)).monospacedDigit()
                        let verdict = row.1.map(row.2) ?? ""
                        Text(verdict).font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(verdict == "Even" ? Palette.secondary : Palette.orange)
                            .frame(width: 84, alignment: .trailing)
                    }
                    .frame(height: 40).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func legend(_ t: String, _ c: Color) -> some View {
        HStack(spacing: 5) { RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 9, height: 9); Text(t) }
            .font(.system(size: 12)).foregroundStyle(Palette.secondary)
    }
}

// MARK: - Lifts

struct LiftsTab: View {
    let data: StatsData
    let range: StatsRange
    let onDrill: (StatDrill) -> Void
    @State private var picked: [String]?

    private var candidates: [String] {
        let counts = Dictionary(grouping: data.sets.filter { $0.e1RM > 0 }, by: \.exercise.name).mapValues(\.count)
        return counts.keys.sorted { a, b in
            let pa = TrendsView.bigLifts.firstIndex(of: a) ?? 99, pb = TrendsView.bigLifts.firstIndex(of: b) ?? 99
            return pa != pb ? pa < pb : (counts[a]! == counts[b]! ? a < b : counts[a]! > counts[b]!)
        }
    }

    var body: some View {
        let all = candidates
        let lifts = (picked ?? Array(all.prefix(4))).filter { all.contains($0) }
        VStack(alignment: .leading, spacing: 16) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Array(lifts.enumerated()), id: \.element) { i, name in
                        Button {
                            if lifts.count > 1 { picked = lifts.filter { $0 != name } }
                        } label: {
                            HStack(spacing: 6) {
                                Circle().fill(Stats.colors[i % Stats.colors.count]).frame(width: 8, height: 8)
                                Text(short(name))
                            }
                            .font(.system(size: 15)).padding(.horizontal, 12).frame(height: 32)
                            .background(Palette.card, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    let rest = all.filter { !lifts.contains($0) }
                    if !rest.isEmpty && lifts.count < Stats.colors.count {
                        Menu {
                            ForEach(rest, id: \.self) { n in Button(n) { picked = lifts + [n] } }
                        } label: {
                            Image(systemName: "plus").font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.orange)
                                .frame(width: 32, height: 32).background(Palette.card, in: Circle())
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            changeChart(lifts)
            comparison(lifts)
        }
    }

    private func short(_ n: String) -> String {
        ["Bench Press": "Bench", "Back Squat": "Squat", "Barbell Row": "Row", "Overhead Press": "OHP"][n] ?? n
    }

    private struct Point: Identifiable {
        let id = UUID()
        let lift: String
        let date: Date
        let pct: Double
    }

    private func changeChart(_ lifts: [String]) -> some View {
        let start = range.start
        var points: [Point] = []
        var last: [(String, Double)] = []
        for name in lifts {
            let sets = data.sets.filter { $0.exercise.name == name && $0.e1RM > 0 }
            let sessions = Dictionary(grouping: sets, by: \.workout.persistentModelID).values
                .map { g in (g[0].date, g.map(\.e1RM).max() ?? 0) }.sorted { $0.0 < $1.0 }
            let before = sessions.last { $0.0 < start }
            let inRange = sessions.filter { $0.0 >= start }
            guard let base = (before ?? inRange.first)?.1, base > 0, !inRange.isEmpty else { continue }
            if before != nil { points.append(Point(lift: short(name), date: start, pct: 0)) }
            for s in inRange { points.append(Point(lift: short(name), date: s.0, pct: (s.1 / base - 1) * 100)) }
            last.append((short(name), (inRange.last!.1 / base - 1) * 100))
        }
        let names = lifts.map(short)
        let ranked = last.sorted { $0.1 > $1.1 }
        return Card {
            Text("Est. 1RM change since \(Fmt.date(start, "MMM d"))").font(.system(size: 17, weight: .semibold))
            if ranked.count >= 2 {
                Text("\(ranked.first!.0) is improving fastest; \(ranked.last!.0) is slowest")
                    .font(.system(size: 13)).foregroundStyle(Palette.secondary)
            }
            if points.isEmpty {
                Text("No sets of 10 reps or fewer in this range.").font(.system(size: 15)).foregroundStyle(Palette.secondary).padding(.vertical, 24)
            } else {
                HStack(alignment: .center, spacing: 8) {
                    Chart(points) { p in
                        LineMark(x: .value("Date", p.date), y: .value("Change", p.pct))
                            .foregroundStyle(by: .value("Lift", p.lift))
                            .interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    }
                    .chartForegroundStyleScale(domain: names, range: names.indices.map { Stats.colors[$0 % Stats.colors.count] })
                    .chartLegend(.hidden)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 3)) { v in
                            AxisValueLabel { if let d = v.as(Date.self) { Text(Fmt.date(d, "MMM d")) } }
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { v in
                            AxisGridLine().foregroundStyle(Palette.separator)
                            AxisValueLabel { if let d = v.as(Double.self) { Text("\(d > 0 ? "+" : "")\(Int(d))%") } }
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(ranked, id: \.0) { n, pct in
                            Text("\(n) \(pct >= 0 ? "+" : "−")\(Int(abs(pct).rounded()))%")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Stats.colors[(names.firstIndex(of: n) ?? 0) % Stats.colors.count])
                        }
                    }
                    .frame(width: 92, alignment: .leading)
                }
                .frame(height: 170).padding(.top, 12)
            }
        }
    }

    private func comparison(_ lifts: [String]) -> some View {
        let recentStart = StatsRange.w4.start
        let priorStart = Calendar.mondayFirst.date(byAdding: .weekOfYear, value: -4, to: recentStart)!
        return Card {
            Text("Last 4 weeks vs the 4 before").font(.system(size: 17, weight: .semibold))
            HStack {
                Text("LIFT").frame(maxWidth: .infinity, alignment: .leading)
                Text("EST. 1RM").frame(width: 76, alignment: .trailing)
                Text("CHANGE").frame(width: 66, alignment: .trailing)
                Text("SETS").frame(width: 40, alignment: .trailing)
            }
            .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.secondary).padding(.top, 14).padding(.bottom, 6)
            ForEach(lifts, id: \.self) { name in
                let sets = data.sets.filter { $0.exercise.name == name }
                let recent = sets.filter { $0.date >= recentStart }
                let prior = sets.filter { $0.date >= priorStart && $0.date < recentStart }
                let r = recent.map(\.e1RM).max() ?? 0, p = prior.map(\.e1RM).max() ?? 0
                RowDivider()
                Button { onDrill(StatDrill(title: "\(name), last 4 weeks", sets: recent)) } label: {
                    HStack {
                        Text(name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        Text(r > 0 ? Fmt.wu(r.rounded()) : "–").monospacedDigit().frame(width: 76, alignment: .trailing)
                        Text(r > 0 && p > 0 ? "\(r >= p ? "+" : "−")\(Fmt.w(abs(r - p).rounded())) \(Units.unitLabel)" : "–")
                            .foregroundStyle(r >= p ? Palette.orange : Palette.secondary).monospacedDigit()
                            .frame(width: 66, alignment: .trailing)
                        Text("\(recent.count)").foregroundStyle(Palette.secondary).monospacedDigit().frame(width: 40, alignment: .trailing)
                    }
                    .font(.system(size: 15)).frame(height: 42).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Habits

struct HabitsTab: View {
    let data: StatsData
    let range: StatsRange
    let onDrill: (StatDrill) -> Void
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        let start = range.start
        let sets = data.sets(from: start)
        let workouts = data.workouts(from: start)
        let cal = Calendar.current
        let byDay = Dictionary(grouping: sets) { cal.startOfDay(for: $0.date) }
        let dayVolume = byDay.mapValues { $0.reduce(0) { $0 + $1.volume } }
        let nonzero = dayVolume.values.filter { $0 > 0 }.sorted()
        let t1 = nonzero.isEmpty ? 0 : nonzero[nonzero.count / 3]
        let t2 = nonzero.isEmpty ? 0 : nonzero[(nonzero.count * 2) / 3]
        let weeks = range.rawValue
        let weekCounts = (0..<weeks).map { w -> Int in
            let s = Calendar.mondayFirst.date(byAdding: .weekOfYear, value: w, to: start)!
            let e = Calendar.mondayFirst.date(byAdding: .weekOfYear, value: 1, to: s)!
            return workouts.filter { $0.startedAt >= s && $0.startedAt < e }.count
        }
        VStack(alignment: .leading, spacing: 12) {
            Card {
                Text("Training days").font(.system(size: 17, weight: .semibold))
                Text("Darker means more volume that day · tap a day to open it")
                    .font(.system(size: 13)).foregroundStyle(Palette.secondary).padding(.bottom, 10)
                heatmap(start: start, weeks: weeks, byDay: byDay) { day in
                    guard let v = dayVolume[day] else { return 0 }
                    return v <= t1 ? 1 : (v <= t2 ? 2 : 3)
                }
                HStack(spacing: 4) {
                    Text("Rest day")
                    ForEach(0..<4) { l in RoundedRectangle(cornerRadius: 2).fill(level(l)).frame(width: 10, height: 10) }
                    Text("Heavy day")
                }
                .font(.system(size: 12)).foregroundStyle(Palette.secondary).padding(.top, 10)
            }
            let goal = max(1, settings.weeklyLiftGoal)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                tile(Fmt.num(Double(workouts.count) / Double(weeks), maxDecimals: 1), weeks == 1 ? "sessions this week" : "sessions a week")
                tile("\(weekCounts.filter { $0 >= goal }.count) of \(weeks)", "week\(weeks == 1 ? "" : "s") hit your \(goal)-session goal")
                tile(usualDays(workouts, weeks: weeks), "your usual days")
                typicalStart(workouts)
            }
            sinceLastTrained
        }
    }

    private func level(_ l: Int) -> Color {
        [Palette.field, Palette.orange.opacity(0.35), Palette.orange.opacity(0.65), Palette.orange][l]
    }

    private func heatmap(start: Date, weeks: Int, byDay: [Date: [StatSet]], level levelFor: @escaping (Date) -> Int) -> some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekStarts = (0..<weeks).map { Calendar.mondayFirst.date(byAdding: .weekOfYear, value: $0, to: start)! }
        let gap: CGFloat = weeks > 26 ? 1 : 3
        let h: CGFloat = weeks > 26 ? 10 : (weeks > 12 ? 14 : 20)
        let letters = ["M", "T", "W", "T", "F", "S", "S"]
        return VStack(spacing: gap) {
            HStack(spacing: gap) {
                Color.clear.frame(width: 16, height: 12)
                ForEach(Array(weekStarts.enumerated()), id: \.offset) { i, w in
                    let month = cal.component(.month, from: w)
                    let label = i == 0 || month != cal.component(.month, from: weekStarts[i - 1]) ? Fmt.date(w, "MMM") : ""
                    Color.clear.frame(maxWidth: .infinity).frame(height: 12)
                        .overlay(alignment: .leading) { Text(label).font(.system(size: 11)).foregroundStyle(Palette.secondary).fixedSize() }
                }
            }
            ForEach(0..<7, id: \.self) { d in
                HStack(spacing: gap) {
                    Text(letters[d]).font(.system(size: 11)).foregroundStyle(Palette.secondary).frame(width: 16, alignment: .leading)
                    ForEach(Array(weekStarts.enumerated()), id: \.offset) { _, w in
                        let day = cal.startOfDay(for: cal.date(byAdding: .day, value: d, to: w)!)
                        if day > today {
                            Color.clear.frame(maxWidth: .infinity).frame(height: h)
                        } else {
                            let l = levelFor(day)
                            RoundedRectangle(cornerRadius: weeks > 26 ? 1.5 : 3).fill(level(l))
                                .frame(maxWidth: .infinity).frame(height: h)
                                .onTapGesture {
                                    if let s = byDay[day] { onDrill(StatDrill(title: Fmt.date(day, "EEEE, MMM d"), sets: s)) }
                                }
                        }
                    }
                }
            }
        }
    }

    private func tile(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 22, weight: .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(caption).font(.system(size: 12)).foregroundStyle(Palette.secondary).lineLimit(2)
        }
        .padding(12).frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
    }

    private func usualDays(_ workouts: [Workout], weeks: Int) -> String {
        let names = ["M", "T", "W", "Th", "F", "Sa", "Su"]
        var weeksPerDay = [Set<Date>](repeating: [], count: 7)
        for w in workouts { weeksPerDay[Stats.weekdayIndex(w.startedAt)].insert(Analytics.weekStart(w.startedAt)) }
        let threshold = max(1, Int((Double(weeks) * 0.4).rounded()))
        let days = (0..<7).filter { weeksPerDay[$0].count >= threshold }.map { names[$0] }
        return days.isEmpty ? "–" : days.joined(separator: " · ")
    }

    private func typicalStart(_ workouts: [Workout]) -> some View {
        let cal = Calendar.current
        let minutes = workouts.map { w -> Double in
            let c = cal.dateComponents([.hour, .minute], from: w.startedAt)
            return Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
        }
        let durations = workouts.map { $0.duration / 60 }
        guard let m = Stats.median(minutes), let d = Stats.median(durations) else { return tile("–", "typical start") }
        let time = cal.startOfDay(for: Date()).addingTimeInterval(m * 60)
        return tile(Fmt.time(time), "typical start · \(Int(d.rounded())) min long")
    }

    private var sinceLastTrained: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let groups: [(String, MuscleGroup)] = [("Back", .back), ("Chest", .chest), ("Shoulders", .shouldersArms), ("Legs", .legs)]
        let windowStart = StatsRange.w12.start
        return Card {
            Text("Since last trained").font(.system(size: 17, weight: .semibold)).padding(.bottom, 10)
            HStack(spacing: 8) {
                ForEach(groups, id: \.0) { label, g in
                    let sets = data.sets.filter { $0.primary?.group == g }
                    let days = Set(sets.map { cal.startOfDay(for: $0.date) }).sorted()
                    let since = days.last.map { cal.dateComponents([.day], from: $0, to: today).day ?? 0 }
                    let recent = days.filter { $0 >= windowStart }
                    let gaps = zip(recent, recent.dropFirst()).map { Double(cal.dateComponents([.day], from: $0, to: $1).day ?? 0) }
                    let typical = Stats.median(gaps) ?? 0
                    let due = since.map { typical > 0 && Double($0) > typical } ?? false
                    Button {
                        if let last = days.last { onDrill(StatDrill(title: "\(label), \(Fmt.date(last, "MMM d"))", sets: sets.filter { cal.startOfDay(for: $0.date) == last })) }
                    } label: {
                        VStack(spacing: 2) {
                            Text(due ? "\(label) · due" : label).font(.system(size: 12)).foregroundStyle(due ? Palette.orange : Palette.secondary).lineLimit(1)
                            Text(since.map { "\($0) day\($0 == 1 ? "" : "s")" } ?? "–").font(.system(size: 17, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(Palette.field, in: RoundedRectangle(cornerRadius: 10))
                        .overlay { if due { RoundedRectangle(cornerRadius: 10).stroke(Palette.orange, lineWidth: 1.5) } }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Effort

struct EffortTab: View {
    let data: StatsData
    let range: StatsRange
    let onDrill: (StatDrill) -> Void

    var body: some View {
        let sets = data.sets(from: range.start).filter { $0.reps > 0 }
        VStack(alignment: .leading, spacing: 16) {
            repRanges(sets)
            rpe(sets)
            equipment(data.sets(from: range.start))
        }
    }

    private func repRanges(_ sets: [StatSet]) -> some View {
        let buckets = RepRange.allCases.map { r in (r, sets.filter { RepRange(reps: $0.reps) == r }) }
        let total = max(1, sets.count)
        let top = buckets.max { $0.1.count < $1.1.count }
        return Card {
            Text("Sets by rep range").font(.system(size: 17, weight: .semibold))
            Text("Most of your work is \(top.map { $0.0.title } ?? "–") · \(sets.count) working sets")
                .font(.system(size: 13)).foregroundStyle(Palette.secondary)
            bars(buckets.map { b in
                (b.0.title, "\(Int((Double(b.1.count) / Double(total) * 100).rounded()))%", Double(b.1.count), b.1)
            })
        }
    }

    private func rpe(_ sets: [StatSet]) -> some View {
        let rated = sets.filter { $0.record.rpe > 0 }
        let labels = ["RPE ≤6", "7", "8", "9", "10"]
        let buckets = labels.indices.map { i in
            (labels[i], rated.filter { s in
                let v = Int(s.record.rpe.rounded(.down))
                return i == 0 ? v <= 6 : v == i + 6
            })
        }
        return Card {
            Text("How hard your sets were").font(.system(size: 17, weight: .semibold))
            Text("RPE 10 = no reps left · logged on \(rated.count) of \(sets.count) sets")
                .font(.system(size: 13)).foregroundStyle(Palette.secondary)
            if rated.isEmpty {
                Text("Tap an RPE in the set keypad when you log reps, and this fills in.")
                    .font(.system(size: 15)).foregroundStyle(Palette.secondary).padding(.vertical, 20)
            } else {
                bars(buckets.map { ($0.0, "\($0.1.count)", Double($0.1.count), $0.1) })
            }
        }
    }

    private func bars(_ items: [(String, String, Double, [StatSet])]) -> some View {
        let maxV = max(1, items.map(\.2).max() ?? 1)
        return HStack(alignment: .bottom, spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Button { onDrill(StatDrill(title: item.0, sets: item.3)) } label: {
                    VStack(spacing: 6) {
                        Text(item.1).font(.system(size: 15, weight: .bold)).monospacedDigit()
                        RoundedRectangle(cornerRadius: 4).fill(Palette.orange)
                            .frame(height: max(4, 110 * item.2 / maxV))
                        Text(item.0).font(.system(size: 12)).foregroundStyle(Palette.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 170, alignment: .bottom).padding(.top, 12)
    }

    private func equipment(_ sets: [StatSet]) -> some View {
        let total = sets.reduce(0) { $0 + $1.volume }
        let rows = Equipment.allCases.map { e in (e, sets.filter { $0.exercise.equipment == e }) }
            .map { ($0.0, $0.1, $0.1.reduce(0) { $0 + $1.volume }) }
            .filter { $0.2 > 0 }.sorted { $0.2 > $1.2 }
        return Card {
            Text("Volume by equipment").font(.system(size: 17, weight: .semibold))
            if total <= 0 {
                Text("No weighted sets in this range.").font(.system(size: 15)).foregroundStyle(Palette.secondary).padding(.vertical, 12)
            } else {
                GeometryReader { g in
                    HStack(spacing: 2) {
                        ForEach(rows, id: \.0) { e, _, v in
                            Rectangle().fill(Stats.equipmentColor(e)).frame(width: max(2, (g.size.width - CGFloat(rows.count - 1) * 2) * v / total))
                        }
                    }
                }
                .frame(height: 14).clipShape(Capsule()).padding(.top, 12)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible())], spacing: 8) {
                    ForEach(rows, id: \.0) { e, s, v in
                        Button { onDrill(StatDrill(title: e.title, sets: s)) } label: {
                            HStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 2).fill(Stats.equipmentColor(e)).frame(width: 10, height: 10)
                                Text(e.title)
                                Spacer()
                                Text("\(Int((v / total * 100).rounded()))%").fontWeight(.semibold).monospacedDigit()
                            }
                            .font(.system(size: 15)).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 12)
            }
        }
    }
}

// MARK: - Drill-down

struct StatDrillSheet: View {
    let drill: StatDrill
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let groups = Dictionary(grouping: drill.sets) { $0.workout.persistentModelID }.values
            .map { g in g.sorted { ($0.record.entry?.order ?? 0, $0.record.order) < ($1.record.entry?.order ?? 0, $1.record.order) } }
            .sorted { $0[0].date > $1[0].date }
        NavigationStack {
            List {
                if drill.sets.isEmpty {
                    Text("No sets").foregroundStyle(Palette.secondary)
                }
                ForEach(Array(groups.enumerated()), id: \.offset) { _, g in
                    Section {
                        ForEach(g) { s in
                            HStack {
                                Text(s.exercise.name).lineLimit(1)
                                Spacer()
                                Text(Analytics.setText(s.record, s.exercise.kind)).monospacedDigit()
                                if s.record.rpe > 0 {
                                    Text("@\(Fmt.num(s.record.rpe))").foregroundStyle(Palette.secondary).monospacedDigit()
                                }
                            }
                            .font(.system(size: 15))
                        }
                    } header: {
                        Text("\(Fmt.date(g[0].date, "EEE, MMM d")) · \(g[0].workout.name)")
                    }
                }
            }
            .scrollContentBackground(.hidden).background(Color.black)
            .navigationTitle("\(drill.title) · \(drill.sets.count) set\(drill.sets.count == 1 ? "" : "s")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.tint(Palette.orange) } }
        }
        .preferredColorScheme(.dark)
    }
}
