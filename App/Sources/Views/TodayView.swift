import SwiftData
import SwiftUI

struct TodayView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var health: HealthStore
    @EnvironmentObject var session: WorkoutSession
    @EnvironmentObject var router: Router
    @Query(sort: \Workout.startedAt, order: .reverse) private var workouts: [Workout]
    @Query(sort: \Routine.order) private var routines: [Routine]

    private var finished: [Workout] { workouts.filter { $0.endedAt != nil } }

    var body: some View {
        Screen {
            LargeTitle(title: "Today", eyebrow: Fmt.date(Date(), "EEEE, MMM d"),
                       trailing: finished.isEmpty ? nil : AnyView(CircleIconButton(system: "gearshape") { router.push(.settings) }))
            if finished.isEmpty {
                FirstDayView()
            } else {
                trendCard
                weekCard
                nextUpCard
                recentPRs
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Trend weight
    @ViewBuilder private var trendCard: some View {
        let points = BodyMath.trend(health.weights)
        if let last = points.last {
            Button { router.tab = .body } label: {
                Card {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Trend weight").font(.system(size: 17, weight: .semibold))
                        Spacer()
                        if let s = health.latestHealthWeight {
                            Text("\(s.source) · \(Fmt.time(s.date))").font(.system(size: 13)).foregroundStyle(Palette.secondary)
                        }
                    }
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(Fmt.fixed(Units.display(last.trend), 1)).font(.system(size: 34, weight: .bold)).monospacedDigit()
                                Text(Units.unitLabel).font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.secondary)
                            }
                            if let c = BodyMath.change(points, days: 30) {
                                Text("\(Fmt.signedW(c)) \(Units.unitLabel) in 30 days").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.cyan)
                            }
                        }
                        Spacer()
                        Sparkline(values: points.suffix(30).map(\.trend), tint: Palette.cyan, dot: true)
                            .frame(width: 130, height: 44)
                    }
                    .padding(.top, 6)
                }
            }
            .buttonStyle(.plain)
        } else if !health.isConnected {
            NoticeCard(icon: "heart.text.square", tint: Palette.cyan, title: "Connect Apple Health",
                       message: "Bring in Renpho weigh-ins and runs to see trend weight here.",
                       actionTitle: "Connect") { Task { await health.requestAccess() } }
        }
    }

    // MARK: This week
    private var weekCard: some View {
        let start = Analytics.weekStart()
        let week = Analytics.workouts(finished, inWeekOf: start)
        let runs = health.runs.filter { $0.start >= start }
        let miles = runs.reduce(0) { $0 + Units.runDisplay($1.meters) }
        let runTime = runs.reduce(0) { $0 + $1.duration }
        let prs = week.reduce(0) { $0 + Analytics.workoutPRs($1).count }
        let runGoal = settings.unit == .lb ? settings.weeklyRunGoal : settings.weeklyRunGoal * 1.609344
        return Card {
            CardTitle(title: "This week", trailing: Fmt.weekRange(start))
            VStack(spacing: 14) {
                goalRow("Lifting", value: "\(week.count)", goal: "/ \(settings.weeklyLiftGoal) sessions",
                        progress: Double(week.count) / Double(max(1, settings.weeklyLiftGoal)), tint: Palette.orange)
                goalRow("Running", value: Fmt.fixed(miles, 1), goal: "/ \(Fmt.num(runGoal, maxDecimals: 0)) \(Units.runLabel)",
                        progress: miles / max(1, runGoal), tint: Palette.cyan)
            }
            .padding(.top, 14)
            HStack {
                StatColumn(label: "Volume", value: "\(Fmt.num(Units.display(week.reduce(0) { $0 + $1.volume }), maxDecimals: 0)) \(Units.unitLabel)")
                StatColumn(label: "Run time", value: Fmt.duration(runTime))
                StatColumn(label: "PRs", value: "\(prs)")
            }
            .padding(.top, 16)
        }
    }

    private func goalRow(_ label: String, value: String, goal: String, progress: Double, tint: Color) -> some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(.system(size: 17))
                Spacer()
                Text(value).font(.system(size: 17, weight: .semibold)).monospacedDigit()
                    + Text(" \(goal)").font(.system(size: 17)).foregroundColor(Palette.secondary)
            }
            ProgressBar(value: progress, tint: tint)
        }
    }

    // MARK: Next up
    @ViewBuilder private var nextUpCard: some View {
        if session.isActive {
            Card {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("IN PROGRESS").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.orange)
                        Text(session.workout?.name ?? "Workout").font(.system(size: 22, weight: .bold))
                        Text("\(session.setsDone) sets done").font(.system(size: 13)).foregroundStyle(Palette.secondary)
                    }
                    Spacer()
                    startButton("Resume") { session.isPresented = true }
                }
            }
        } else if let next = Analytics.nextRoutine(routines, workouts: finished) {
            Card {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("NEXT UP").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.orange)
                        Text(next.name.hasSuffix("Day") ? next.name : "\(next.name) Day").font(.system(size: 22, weight: .bold))
                        Text("\(next.items.count) exercises" + (next.lastPerformed.map { " · last done \(Fmt.relativeDay($0))" } ?? ""))
                            .font(.system(size: 13)).foregroundStyle(Palette.secondary)
                    }
                    Spacer()
                    startButton("Start") { session.start(routine: next) }
                }
            }
        }
    }

    private func startButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(.black)
                .frame(width: 110, height: 44).background(Palette.orange, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Recent PRs
    @ViewBuilder private var recentPRs: some View {
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: Date())!
        let prs = finished.filter { $0.startedAt >= cutoff }.prefix(6).flatMap { Analytics.workoutPRs($0) }.prefix(3)
        if !prs.isEmpty {
            Card {
                Text("Recent PRs").font(.system(size: 17, weight: .semibold)).padding(.bottom, 8)
                ForEach(Array(prs.enumerated()), id: \.element.id) { i, pr in
                    if i > 0 { RowDivider() }
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pr.exerciseName).font(.system(size: 17))
                            Text("\(Fmt.relativeDay(pr.date)) · \(pr.shortDetail)").font(.system(size: 13)).foregroundStyle(Palette.secondary)
                        }
                        Spacer()
                        Text(pr.value).font(.system(size: 17, weight: .bold)).foregroundStyle(Palette.orange).monospacedDigit()
                    }
                    .padding(.vertical, 9)
                }
            }
        }
    }
}

struct FirstDayView: View {
    @EnvironmentObject var health: HealthStore
    @EnvironmentObject var session: WorkoutSession
    @EnvironmentObject var router: Router
    @Environment(\.modelContext) private var context
    @Query(sort: \Routine.order) private var routines: [Routine]

    var body: some View {
        Card {
            Text("Log your first workout").font(.system(size: 22, weight: .bold))
            Text("Pick a starter routine and change it as you go, or start empty and add exercises.")
                .font(.system(size: 15)).foregroundStyle(Palette.secondary).padding(.top, 4)
            HStack(spacing: 8) {
                ForEach(Library.starters, id: \.name) { s in
                    Button { start(s) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(s.name).font(.system(size: 17, weight: .semibold))
                            Text(s.blurb).font(.system(size: 12)).foregroundStyle(Palette.secondary).multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(12).frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
                        .background(Palette.field, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 14)
            PrimaryButton(title: "Start empty workout") { session.start(routine: nil) }.padding(.top, 14)
            Button { router.push(.importNotes) } label: {
                Text("Already tracking in Notes? Import it").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.orange)
                    .frame(maxWidth: .infinity)
            }
            .padding(.top, 14)
        }
        healthCard
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 13)).foregroundStyle(Palette.secondary)
            Text("Trends that combine lifting with weight and runs appear after about two weeks of workouts.")
                .font(.system(size: 13)).foregroundStyle(Palette.secondary)
        }
        .padding(.horizontal, 8)
    }

    @ViewBuilder private var healthCard: some View {
        let weights = health.weights.filter { !$0.isManual }
        if health.isConnected && (!weights.isEmpty || !health.runs.isEmpty) {
            Card {
                Text("ALREADY IN FROM APPLE HEALTH").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.secondary).padding(.bottom, 6)
                if let first = weights.first, let last = weights.last {
                    row("Weight", "\(weights.count) \(sourceName(weights)) weigh-ins since \(Fmt.date(first.date, "MMMM"))",
                        "\(Fmt.fixed(Units.display(last.value), 1)) \(Units.unitLabel)")
                }
                if !weights.isEmpty && !health.runs.isEmpty { RowDivider() }
                if let firstRun = health.runs.last {
                    row("Runs", "Since \(Fmt.date(firstRun.start, "MMMM")), from \(firstRun.source)", "\(health.runs.count) runs")
                }
            }
        } else if !health.isConnected {
            NoticeCard(icon: "heart.text.square", tint: Palette.cyan, title: "Connect Apple Health",
                       message: "Bring in Renpho weigh-ins and Apple Watch runs. Lifting works without it.",
                       actionTitle: "Connect") { Task { await health.requestAccess() } }
        }
    }

    private func sourceName(_ s: [BodySample]) -> String {
        Dictionary(grouping: s, by: \.source).max { $0.value.count < $1.value.count }?.key ?? ""
    }

    private func row(_ title: String, _ sub: String, _ value: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 17))
                Text(sub).font(.system(size: 13)).foregroundStyle(Palette.secondary)
            }
            Spacer()
            Text(value).font(.system(size: 17, weight: .bold)).foregroundStyle(Palette.cyan)
        }
        .padding(.vertical, 8)
    }

    private func start(_ s: Library.Starter) {
        let r = routines.first { $0.name == s.name } ?? Library.createStarter(s, in: context)
        session.start(routine: r)
    }
}
