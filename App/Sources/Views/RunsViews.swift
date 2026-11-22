import Charts
import MapKit
import SwiftData
import SwiftUI

enum RunClassifier {
    /// Uses the user's tag if they set one; otherwise a simple guess from distance and pace.
    static func kind(_ run: RunSummary, tags: [RunTag], all: [RunSummary]) -> RunKind {
        if let t = tags.first(where: { $0.workoutID == run.id }) { return t.kind }
        let miles = run.meters / Units.metersPerMile
        let recent = all.filter { abs($0.start.timeIntervalSince(run.start)) < 60 * 86400 }
        let avgPace = recent.map { $0.duration / max(0.1, $0.meters / Units.metersPerMile) }.reduce(0, +) / Double(max(1, recent.count))
        let pace = run.duration / max(0.1, miles)
        if miles >= 7.5 { return .long }
        if pace < avgPace * 0.92 { return .tempo }
        return .easy
    }
}

struct RunsListView: View {
    @EnvironmentObject var health: HealthStore
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var router: Router
    @Query private var tags: [RunTag]

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 4) {
                Text("Runs").font(.system(size: 34, weight: .bold))
                if !health.runs.isEmpty { Text("Synced from Apple Health").font(.system(size: 13)).foregroundStyle(Palette.secondary) }
            }
            .padding(.top, 8)
            if health.runs.isEmpty {
                NoRunsView()
            } else {
                summary
                ForEach(weeks, id: \.start) { week in
                    let isThis = week.start == Analytics.weekStart()
                    let total = week.runs.reduce(0) { $0 + Units.runDisplay($1.meters) }
                    Text(isThis ? "This week" : "\(week.start == Calendar.current.date(byAdding: .day, value: -7, to: Analytics.weekStart())! ? "Last week" : Fmt.weekRange(week.start)) · \(Fmt.fixed(total, 1)) \(Units.runLabel) · \(week.runs.count) run\(week.runs.count == 1 ? "" : "s")")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.secondary).padding(.horizontal, 4).padding(.top, 4)
                    Card(padding: 0) {
                        ForEach(Array(week.runs.enumerated()), id: \.element.id) { i, run in
                            if i > 0 { RowDivider(inset: 16) }
                            Button { router.push(.run(run.id)) } label: { row(run) }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var weeks: [(start: Date, runs: [RunSummary])] {
        Dictionary(grouping: health.runs.prefix(60)) { Analytics.weekStart($0.start) }
            .map { ($0.key, $0.value.sorted { $0.start > $1.start }) }
            .sorted { $0.0 > $1.0 }
    }

    private var summary: some View {
        let start = Analytics.weekStart()
        let thisWeek = health.runs.filter { $0.start >= start }.reduce(0) { $0 + Units.runDisplay($1.meters) }
        let eight = (1...8).map { w -> Double in
            let s = Calendar.current.date(byAdding: .day, value: -7 * w, to: start)!
            let e = Calendar.current.date(byAdding: .day, value: 7, to: s)!
            return health.runs.filter { $0.start >= s && $0.start < e }.reduce(0) { $0 + Units.runDisplay($1.meters) }
        }
        let goal = settings.unit == .lb ? settings.weeklyRunGoal : settings.weeklyRunGoal * 1.609344
        return Card {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("This week").font(.system(size: 13)).foregroundStyle(Palette.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(Fmt.fixed(thisWeek, 1)).font(.system(size: 34, weight: .bold)).monospacedDigit()
                        Text("/ \(Fmt.num(goal, maxDecimals: 0)) \(Units.runLabel)").font(.system(size: 17)).foregroundStyle(Palette.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("8-week avg").font(.system(size: 13)).foregroundStyle(Palette.secondary)
                    Text("\(Fmt.fixed(eight.reduce(0, +) / 8, 1)) \(Units.runLabel)").font(.system(size: 20, weight: .bold)).monospacedDigit()
                }
            }
            Chart {
                ForEach(Array(eight.reversed().enumerated()), id: \.offset) { i, v in
                    BarMark(x: .value("Week", i), y: .value("Distance", v)).foregroundStyle(Palette.cyan.opacity(0.45)).cornerRadius(3)
                }
                BarMark(x: .value("Week", 8), y: .value("Distance", thisWeek)).foregroundStyle(Palette.cyan).cornerRadius(3)
                RuleMark(y: .value("Goal", goal)).foregroundStyle(Palette.secondary.opacity(0.6)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            .chartXAxis(.hidden).chartYAxis(.hidden)
            .frame(height: 70).padding(.top, 12)
        }
    }

    private func row(_ run: RunSummary) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(RunClassifier.kind(run, tags: tags, all: health.runs).title).font(.system(size: 17))
                Text("\(Fmt.date(run.start, "EEE, MMM d")) · \(Fmt.pace(seconds: run.duration, meters: run.meters)) /\(Units.runLabel)")
                    .font(.system(size: 13)).foregroundStyle(Palette.secondary)
            }
            Spacer()
            Text("\(Fmt.runDist(run.meters, decimals: Units.runDisplay(run.meters) >= 8 ? 2 : 1)) \(Units.runLabel)").font(.system(size: 17, weight: .bold)).monospacedDigit()
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.tertiary)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

struct NoRunsView: View {
    @EnvironmentObject var health: HealthStore
    var body: some View {
        Card {
            Image(systemName: "figure.run").font(.system(size: 22, weight: .semibold)).foregroundStyle(Palette.cyan)
                .frame(width: 44, height: 44).background(Palette.cyan.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
            Text("No runs coming through").font(.system(size: 22, weight: .bold)).padding(.top, 12)
            Text("Either this app's Apple Health access is off, or nothing on your phone or watch is recording runs yet.")
                .font(.system(size: 15)).foregroundStyle(Palette.secondary).padding(.top, 4).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 14) {
                step(1, "Check access", "Settings › Health › Data Access & Devices › Lift + Run + Body › Turn On All")
                step(2, "Record a run", "Use the Workout app on Apple Watch, or any running app that saves to Apple Health")
            }
            .padding(.top, 16)
            PrimaryButton(title: health.access == .notRequested ? "Connect Apple Health" : "Open Health settings", tint: Palette.cyan) {
                if health.access == .notRequested { Task { await health.requestAccess() } }
                else if let url = URL(string: "x-apple-health://") { UIApplication.shared.open(url) }
            }
            .padding(.top, 18)
            Text("Lifting and manual weigh-ins keep working without it.").font(.system(size: 13)).foregroundStyle(Palette.secondary)
                .frame(maxWidth: .infinity).padding(.top, 10)
        }
    }

    private func step(_ n: Int, _ title: String, _ sub: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)").font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.cyan)
                .frame(width: 28, height: 28).background(Palette.cyan.opacity(0.16), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 17, weight: .semibold))
                Text(sub).font(.system(size: 13)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct RunDetailView: View {
    let runID: UUID
    @EnvironmentObject var health: HealthStore
    @Environment(\.modelContext) private var context
    @Query private var tags: [RunTag]
    @State private var detail: RunDetail?

    var body: some View {
        if let run = health.runs.first(where: { $0.id == runID }) {
            content(run).task(id: runID) { detail = await health.detail(for: run) }
        } else {
            Text("Run not found").foregroundStyle(Palette.secondary).screenBackground()
        }
    }

    private func content(_ run: RunSummary) -> some View {
        let kind = RunClassifier.kind(run, tags: tags, all: health.runs)
        return Screen {
            VStack(alignment: .leading, spacing: 4) {
                Text(kind.title).font(.system(size: 34, weight: .bold))
                Text("\(Fmt.date(run.start, "EEE, MMM d")) · \(Fmt.time(run.start))").font(.system(size: 15)).foregroundStyle(Palette.secondary)
            }
            map(run)
            Card {
                HStack(alignment: .top) {
                    StatColumn(label: "Distance", value: Fmt.runDist(run.meters, decimals: 2), unit: Units.runLabel)
                    StatColumn(label: "Time", value: Fmt.clock(Int(run.duration)))
                    StatColumn(label: "Avg pace", value: Fmt.pace(seconds: run.duration, meters: run.meters), unit: "/\(Units.runLabel)")
                    StatColumn(label: "Avg HR", value: (detail?.avgHR ?? run.avgHR).map { "\(Int($0))" } ?? "–", unit: "bpm")
                }
            }
            HStack(spacing: 8) {
                ForEach([RunKind.easy, .tempo, .long, .race], id: \.self) { k in
                    Chip(title: k.chip, selected: kind == k, tint: Palette.cyan) { tag(run, k) }
                }
            }
            splits
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Text("From \(run.source)").font(.system(size: 13)).foregroundStyle(Palette.secondary) } }
    }

    @ViewBuilder private func map(_ run: RunSummary) -> some View {
        let route = detail?.route ?? []
        ZStack(alignment: .bottomTrailing) {
            if route.count > 1 {
                Map(initialPosition: .automatic, interactionModes: []) {
                    ForEach(segments(route), id: \.0) { _, coords, speed in
                        MapPolyline(coordinates: coords).stroke(Palette.cyan.opacity(0.35 + 0.65 * speed), lineWidth: 4)
                    }
                    Annotation("", coordinate: route.first!.coordinate) { Circle().fill(.white).frame(width: 10, height: 10) }
                    Annotation("", coordinate: route.last!.coordinate) { Circle().fill(Palette.cyan).frame(width: 10, height: 10).overlay(Circle().stroke(.black, lineWidth: 2)) }
                }
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                .environment(\.colorScheme, .dark)
                HStack(spacing: 6) {
                    Text("Slower")
                    LinearGradient(colors: [Palette.cyan.opacity(0.35), Palette.cyan], startPoint: .leading, endPoint: .trailing).frame(width: 40, height: 3)
                    Text("Faster")
                }
                .font(.system(size: 11)).padding(.horizontal, 8).padding(.vertical, 4).background(.black.opacity(0.6), in: Capsule()).padding(8)
            } else {
                Palette.card
                Text(detail == nil ? "Loading route…" : "No route recorded").font(.system(size: 13)).foregroundStyle(Palette.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// Splits the route into ~20 chunks, each with a 0–1 relative speed for coloring.
    private func segments(_ r: [RoutePoint]) -> [(Int, [CLLocationCoordinate2D], Double)] {
        let n = max(1, r.count / 20)
        var chunks: [(Int, [RoutePoint])] = []
        var i = 0
        while i < r.count - 1 { chunks.append((i, Array(r[i...min(r.count - 1, i + n)]))); i += n }
        let speeds = chunks.map { c -> Double in
            let d = zip(c.1, c.1.dropFirst()).reduce(0.0) { $0 + CLLocation(latitude: $1.0.latitude, longitude: $1.0.longitude).distance(from: CLLocation(latitude: $1.1.latitude, longitude: $1.1.longitude)) }
            let t = max(1, c.1.last!.time.timeIntervalSince(c.1.first!.time))
            return d / t
        }
        let lo = speeds.min() ?? 0, hi = speeds.max() ?? 1
        return zip(chunks, speeds).map { ($0.0, $0.1.map(\.coordinate), hi > lo ? ($1 - lo) / (hi - lo) : 1) }
    }

    @ViewBuilder private var splits: some View {
        let s = detail?.splits ?? []
        if !s.isEmpty {
            let fastest = s.filter { $0.fraction > 0.5 }.map(\.seconds).min() ?? 0
            let slowest = s.map(\.seconds).max() ?? 1
            Card {
                HStack {
                    Text(Units.runLabel.uppercased()).frame(width: 28, alignment: .leading)
                    Text("PACE")
                    Spacer()
                    Text("HR")
                }
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.secondary).padding(.bottom, 6)
                ForEach(s) { sp in
                    HStack(spacing: 10) {
                        Text(sp.fraction < 0.99 ? Fmt.fixed(Double(sp.index - 1) + sp.fraction, 1) : "\(sp.index)")
                            .font(.system(size: 15)).frame(width: 28, alignment: .leading).monospacedDigit()
                        Text(Fmt.clock(Int(sp.seconds))).font(.system(size: 15, weight: sp.seconds == fastest ? .bold : .regular))
                            .frame(width: 44, alignment: .leading).monospacedDigit()
                        GeometryReader { g in
                            let frac = 0.35 + 0.65 * (slowest - sp.seconds + 20) / max(1, slowest - fastest + 20)
                            Capsule().fill(Palette.cyan).frame(width: g.size.width * min(1, frac), height: 6).frame(maxHeight: .infinity)
                        }
                        Text(sp.hr.map { "\(Int($0))" } ?? "–").font(.system(size: 15)).foregroundStyle(Palette.secondary).frame(width: 34, alignment: .trailing).monospacedDigit()
                    }
                    .frame(height: 30)
                }
            }
        }
    }

    private func tag(_ run: RunSummary, _ k: RunKind) {
        if let t = tags.first(where: { $0.workoutID == run.id }) { t.kindRaw = k.rawValue } else { context.insert(RunTag(workoutID: run.id, kind: k)) }
        try? context.save()
    }
}
