import Charts
import SwiftData
import SwiftUI

enum ChartRange: String, CaseIterable, Identifiable {
    case m1 = "1M", m3 = "3M", y1 = "1Y", all = "All"
    var id: String { rawValue }
    var days: Int? { switch self { case .m1: 30; case .m3: 90; case .y1: 365; case .all: nil } }
    func start(_ now: Date = Date()) -> Date? { days.map { Calendar.current.date(byAdding: .day, value: -$0, to: now)! } }
}

struct ExerciseHistoryView: View {
    @Bindable var exercise: Exercise
    @State private var metric = 0
    @State private var range: ChartRange = .m3
    @State private var selected: Date?
    @State private var editing = false

    private var sessions: [Session] { Analytics.sessions(exercise) }

    private var metrics: [String] {
        switch exercise.kind {
        case .weightReps: ["Est. 1RM", "Top set", "Volume", "Max reps"]
        case .bodyweight: ["Max reps", "Total reps", "Added weight"]
        case .assisted: ["Least assist", "Max reps"]
        case .timed: ["Longest hold", "Total time"]
        case .distanceWeight:
            ["Heaviest at \(Fmt.dist(carryDistance)) \(Units.distanceLabel)", "Farthest at \(Fmt.w(carryWeight)) \(Units.unitLabel)"]
        }
    }
    private var carryDistance: Double { sessions.last?.entry.targetDistance ?? sessions.last?.farthest ?? 0 }
    private var carryWeight: Double { sessions.last?.topWeight ?? 0 }

    private func value(_ s: Session) -> Double {
        switch (exercise.kind, metric) {
        case (.weightReps, 0): Units.display(s.bestE1RM > 0 ? s.bestE1RM : s.topWeight)
        case (.weightReps, 1): Units.display(s.topWeight)
        case (.weightReps, 2): Units.display(s.volume)
        case (.weightReps, _), (.bodyweight, 0), (.assisted, 1): Double(s.maxReps)
        case (.bodyweight, 1): Double(s.totalReps)
        case (.bodyweight, _): Units.display(s.topWeight)
        case (.assisted, _): Units.display(s.minWeight)
        case (.timed, 0): Double(s.longest)
        case (.timed, _): Double(s.totalSeconds)
        case (.distanceWeight, 0): Units.display(s.heaviest(atLeast: carryDistance - 0.5))
        case (.distanceWeight, _): Units.distanceDisplay(s.sets.filter { $0.weight >= carryWeight - 0.01 }.map(\.distance).max() ?? 0)
        }
    }

    private func format(_ v: Double) -> (String, String) {
        switch (exercise.kind, metric) {
        case (.timed, _): (Fmt.clock(Int(v)), "")
        case (.weightReps, 3), (.bodyweight, 0), (.bodyweight, 1), (.assisted, 1): (Fmt.num(v, maxDecimals: 0), "reps")
        case (.bodyweight, 2): ("+\(Fmt.num(v))", Units.unitLabel)
        case (.assisted, 0): ("−\(Fmt.num(v))", Units.unitLabel)
        case (.distanceWeight, 0): (Fmt.num(v), "\(Units.unitLabel) × \(Fmt.dist(carryDistance)) \(Units.distanceLabel)")
        case (.distanceWeight, _): (Fmt.num(v, maxDecimals: 0), "\(Units.distanceLabel) × \(Fmt.w(carryWeight)) \(Units.unitLabel)")
        default: (Fmt.num(v, maxDecimals: 0), Units.unitLabel)
        }
    }

    var body: some View {
        let all = sessions
        let start = range.start()
        let shown = all.filter { start == nil || $0.date >= start! }
        Screen {
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name).font(.system(size: 34, weight: .bold))
                Text(subtitle).font(.system(size: 15)).foregroundStyle(Palette.secondary)
            }
            if metrics.count > 1 {
                SegmentedPicker(options: Array(metrics.enumerated()).map { ($0.offset, $0.element) }, selection: $metric)
            }
            if all.isEmpty {
                NoticeCard(icon: "chart.line.uptrend.xyaxis", tint: Palette.orange, title: "No sessions yet",
                           message: "Log \(exercise.name) in a workout and its history, PRs and next target show up here.")
            } else {
                chartCard(shown, all: all)
                switch exercise.kind {
                case .weightReps: repPRs(all)
                case .bodyweight: bodyweightReady(all)
                case .timed, .distanceWeight: nextTarget(all)
                case .assisted: EmptyView()
                }
                if exercise.kind != .weightReps { bests(all) }
                sessionList(all)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Edit") { editing = true }.tint(Palette.orange) } }
        .sheet(isPresented: $editing) { NavigationStack { ExerciseEditorView(existing: exercise) } }
    }

    private var subtitle: String {
        var parts = [exercise.equipmentLabel]
        let muscles = exercise.muscles.filter { !(exercise.equipmentLabel == $0.title) }.map(\.title)
        if !muscles.isEmpty { parts.append(muscles.joined(separator: ", ")) }
        switch exercise.kind {
        case .bodyweight: parts.append("reps + added weight")
        default: parts.append(exercise.kind.title)
        }
        if exercise.perSide { parts.append(exercise.equipment == .dumbbell || exercise.equipment == .kettlebell ? "per hand" : "per side") }
        return parts.joined(separator: " · ")
    }

    // MARK: Chart
    private func chartCard(_ shown: [Session], all: [Session]) -> some View {
        let points = shown.map { (date: $0.date, value: value($0)) }
        let latest = points.last?.value ?? value(all.last!)
        let best = (exercise.kind == .assisted && metric == 0) ? points.map(\.value).min() ?? latest : points.map(\.value).max() ?? latest
        let headline = (exercise.kind == .timed || metric == 0) ? best : latest
        let f = format(headline)
        let first = points.first
        let selectedSession = selected.flatMap { d in shown.min { abs($0.date.timeIntervalSince(d)) < abs($1.date.timeIntervalSince(d)) } }
        return Card {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(f.0).font(.system(size: 34, weight: .bold)).monospacedDigit()
                        Text(f.1).font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.secondary)
                    }
                    if let first, points.count > 1 {
                        Text(changeText(from: first.value, to: headline, since: first.date, count: points.count))
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.orange)
                    }
                }
                Spacer()
                if exercise.kind != .timed {
                    HStack(spacing: 2) {
                        ForEach(ChartRange.allCases) { r in
                            Button(r.rawValue) { range = r }
                                .font(.system(size: 13, weight: range == r ? .semibold : .regular))
                                .foregroundStyle(range == r ? .white : Palette.secondary)
                                .frame(width: 34, height: 26)
                                .background(range == r ? Palette.fieldHigh : .clear, in: Capsule())
                        }
                    }
                }
            }
            chart(points, selectedSession: selectedSession).frame(height: 190).padding(.top, 14)
            if exercise.kind == .weightReps && metric == 0 {
                Text("Estimated from your best set of 10 reps or fewer").font(.system(size: 13)).foregroundStyle(Palette.secondary).padding(.top, 10)
            }
        }
    }

    @ViewBuilder
    private func chart(_ points: [(date: Date, value: Double)], selectedSession: Session?) -> some View {
        let lo = points.map(\.value).min() ?? 0, hi = points.map(\.value).max() ?? 1
        let pad = max(1, (hi - lo) * 0.15)
        if exercise.kind == .timed {
            Chart {
                ForEach(Array(points.suffix(12).enumerated()), id: \.offset) { i, p in
                    BarMark(x: .value("Session", i), y: .value("Value", p.value), width: .ratio(0.7))
                        .foregroundStyle(i == min(points.count, 12) - 1 ? Palette.orange : Palette.orange.opacity(0.55))
                        .cornerRadius(3)
                }
            }
            .chartXAxis {
                AxisMarks(values: [0, min(points.count, 12) - 1]) { v in
                    AxisValueLabel {
                        if let i = v.as(Int.self) { Text(Fmt.date(points.suffix(12)[points.suffix(12).startIndex + i].date, "MMM d")) }
                    }
                }
            }
            .chartYAxis { AxisMarks(position: .trailing) { v in AxisGridLine().foregroundStyle(Palette.separator); AxisValueLabel { if let s = v.as(Double.self) { Text(Fmt.clock(Int(s))) } } } }
        } else {
            Chart {
                ForEach(points, id: \.date) { p in
                    LineMark(x: .value("Date", p.date), y: .value("Value", p.value))
                        .foregroundStyle(Palette.orange).lineStyle(StrokeStyle(lineWidth: 2.5))
                    PointMark(x: .value("Date", p.date), y: .value("Value", p.value))
                        .foregroundStyle(Palette.orange).symbolSize(p.date == points.last?.date ? 60 : 18)
                }
                if let s = selectedSession ?? (points.isEmpty ? nil : sessions.last) {
                    RuleMark(x: .value("Date", s.date)).foregroundStyle(Palette.secondary.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .annotation(position: .top, alignment: .trailing, spacing: 0, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(Fmt.date(s.date, "EEE, MMM d")).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                                Text(annotation(s)).font(.system(size: 12, weight: .semibold))
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Palette.fieldHigh, in: RoundedRectangle(cornerRadius: 6))
                        }
                }
            }
            .chartYScale(domain: (lo - pad)...(hi + pad * 2.5))
            .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
            .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { AxisGridLine().foregroundStyle(Palette.separator); AxisValueLabel() } }
            .chartOverlay { proxy in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { g in selected = proxy.value(atX: g.location.x, as: Date.self) })
            }
        }
    }

    private func annotation(_ s: Session) -> String {
        switch exercise.kind {
        case .weightReps:
            if let b = s.bestE1RMSet, metric == 0 { return "\(Fmt.w(b.weight)) × \(b.reps) → \(Fmt.w(Analytics.e1RM(b.weight, b.reps).rounded())) \(Units.unitLabel)" }
            return s.topSet.map { Analytics.setText($0, exercise.kind) } ?? ""
        default: return s.sets.map { Analytics.setText($0, exercise.kind) }.joined(separator: ", ")
        }
    }

    private func changeText(from a: Double, to b: Double, since: Date, count: Int) -> String {
        let d = b - a
        switch exercise.kind {
        case .timed: return "\(d >= 0 ? "+" : "−")\(Int(abs(d))) s over \(count) sessions"
        case .distanceWeight where metric == 0: return "\(Fmt.signed(d, decimals: 0)) \(Units.unitLabel) per hand since \(Fmt.date(since, "MMM"))"
        default:
            let unit = format(b).1
            return "\(Fmt.signed(d, decimals: 0))\(unit == "reps" ? "" : " \(unit)") since \(Fmt.date(since, "MMM"))"
        }
    }

    // MARK: Weight × reps
    private func repPRs(_ all: [Session]) -> some View {
        let counts = [1, 3, 5, 8, 10]
        var best: [Int: (Double, Date)] = [:]
        for s in all { for set in s.sets where set.reps > 0 {
            for c in counts where set.reps >= c {
                if set.weight > (best[c]?.0 ?? 0) { best[c] = (set.weight, s.date) }
            }
        } }
        let newest = best.values.map(\.1).max()
        return Card {
            HStack(alignment: .firstTextBaseline) {
                Text("Rep PRs").font(.system(size: 17, weight: .semibold))
                Spacer()
                Text("Best weight at each rep count").font(.system(size: 13)).foregroundStyle(Palette.secondary)
            }
            HStack(spacing: 6) {
                ForEach(counts, id: \.self) { c in
                    let b = best[c]
                    let hot = b != nil && b?.1 == newest
                    VStack(spacing: 2) {
                        Text("\(c) rep\(c == 1 ? "" : "s")").font(.system(size: 12)).foregroundStyle(hot ? Palette.orange : Palette.secondary)
                        Text(b.map { Fmt.w($0.0) } ?? "–").font(.system(size: 17, weight: .bold)).monospacedDigit()
                        Text(b.map { Fmt.date($0.1, "MMM d") } ?? " ").font(.system(size: 11)).foregroundStyle(hot ? Palette.orange : Palette.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(hot ? Palette.orange.opacity(0.14) : Palette.field, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(hot ? Palette.orange : .clear, lineWidth: 1))
                }
            }
            .padding(.top, 12)
        }
    }

    // MARK: Bodyweight / timed / carry
    private func bodyweightReady(_ all: [Session]) -> some View {
        let last = all.last!
        let entry = last.entry
        let top = entry.repHigh
        let atTop = last.sets.filter { $0.reps >= top }.count
        return Card {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Ready to add weight?").font(.system(size: 17, weight: .semibold))
                        Spacer()
                        Text("\(atTop) of \(last.sets.count) sets at \(top)+").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.orange)
                    }
                    Text("Last session: \(last.sets.map { "\($0.reps)" }.joined(separator: ", ")). Hit \(top) on all \(numberWord(last.sets.count)) sets and the next session adds \(Fmt.wu(entry.increment)) with a belt.")
                        .font(.system(size: 15)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                    ProgressBar(value: Double(atTop) / Double(max(1, last.sets.count)), tint: Palette.orange, height: 6).padding(.top, 6)
                }
            }
        }
    }

    private func numberWord(_ n: Int) -> String { ["zero", "one", "two", "three", "four", "five", "six"].indices.contains(n) ? ["zero", "one", "two", "three", "four", "five", "six"][n] : "\(n)" }

    private func nextTarget(_ all: [Session]) -> some View {
        let last = all.last!
        let e = last.entry
        let p = Analytics.plan(kind: exercise.kind, config: ProgressionConfig(e), last: last)
        let isTimed = exercise.kind == .timed
        let target = isTimed ? Fmt.clock(p.seconds) : "\(Fmt.wu(p.weight)) × \(Fmt.dist(p.distance)) \(Units.distanceLabel)"
        let rule = isTimed ? "Timed exercises add \(Int(e.increment > 0 && e.increment < 60 ? e.increment : 10)) s once you hold the target on every set"
            : "Carries add \(Fmt.wu(e.increment)) per hand once every set covers the full distance"
        return Card {
            HStack(spacing: 12) {
                Image(systemName: "scope").font(.system(size: 18, weight: .semibold)).foregroundStyle(Palette.orange)
                    .frame(width: 36, height: 36).background(Palette.orange.opacity(0.16), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("Next target: \(target)").font(.system(size: 17, weight: .semibold))
                    Text(rule).font(.system(size: 13)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func bests(_ all: [Session]) -> some View {
        var items: [(String, String, Date)] = []
        func best(_ by: (SetRecord) -> Double) -> (SetRecord, Date)? {
            all.flatMap { s in s.sets.map { ($0, s.date) } }.max { by($0.0) < by($1.0) }
        }
        switch exercise.kind {
        case .bodyweight:
            if let m = best({ Double($0.reps) }) { items.append(("Max reps", "\(m.0.reps)", m.1)) }
            if let t = all.max(by: { $0.totalReps < $1.totalReps }) { items.append(("Best total", "\(t.totalReps)", t.date)) }
            if let h = best({ $0.weight * 100 + Double($0.reps) }), h.0.weight > 0 { items.append(("Heaviest", "+\(Fmt.w(h.0.weight)) × \(h.0.reps)", h.1)) }
        case .assisted:
            if let m = all.flatMap({ s in s.sets.map { ($0, s.date) } }).min(by: { $0.0.weight < $1.0.weight }) { items.append(("Least assist", "−\(Fmt.wu(m.0.weight)) × \(m.0.reps)", m.1)) }
            if let m = best({ Double($0.reps) }) { items.append(("Max reps", "\(m.0.reps)", m.1)) }
        case .timed:
            if let m = best({ Double($0.seconds) }) { items.append(("Longest hold", Fmt.clock(m.0.seconds), m.1)) }
            if let w = best({ $0.weight * 10000 + Double($0.seconds) }), w.0.weight > 0 { items.append(("Best weighted", "+\(Fmt.wu(w.0.weight)) · \(Fmt.clock(w.0.seconds))", w.1)) }
        case .distanceWeight:
            if let h = best({ $0.weight * 10000 + $0.distance }) { items.append(("Heaviest", "\(Fmt.wu(h.0.weight)) × \(Fmt.dist(h.0.distance)) \(Units.distanceLabel)", h.1)) }
            if let f = best({ $0.distance * 10000 + $0.weight }) { items.append(("Farthest", "\(Fmt.dist(f.0.distance)) \(Units.distanceLabel) × \(Fmt.wu(f.0.weight))", f.1)) }
        case .weightReps: break
        }
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
            ForEach(items, id: \.0) { item in
                Card(padding: 12) {
                    Text(item.0).font(.system(size: 13)).foregroundStyle(Palette.secondary)
                    Text(item.1).font(.system(size: 20, weight: .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7).padding(.top, 2)
                    Text(Fmt.date(item.2, "MMM d")).font(.system(size: 12)).foregroundStyle(Palette.secondary).padding(.top, 2)
                }
            }
        }
    }

    private func sessionList(_ all: [Session]) -> some View {
        Card(padding: 0) {
            ForEach(Array(all.reversed().prefix(20).enumerated()), id: \.element.id) { i, s in
                if i > 0 { RowDivider() }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(Fmt.date(s.date, "EEE, MMM d")).font(.system(size: 17, weight: .semibold))
                        Spacer()
                        if Analytics.bestPR(s.entry, prior: Analytics.sessions(exercise, before: s.date)) != nil {
                            Text("PR").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.orange)
                        } else {
                            Text("\(s.sets.count) sets").font(.system(size: 13)).foregroundStyle(Palette.secondary)
                        }
                    }
                    Text(s.sets.map { Analytics.setText($0, exercise.kind) }.joined(separator: " · "))
                        .font(.system(size: 15)).foregroundStyle(Palette.secondary)
                }
                .padding(16)
            }
        }
    }
}
