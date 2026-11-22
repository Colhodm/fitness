import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct LiftRunBodyWidgetBundle: WidgetBundle {
    var body: some Widget {
        TrendWeightWidget()
        NextUpWidget()
        ThisWeekWidget()
        RestTimerLiveActivity()
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snap: WidgetSnapshot
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: Date(), snap: .preview) }
    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(), snap: WidgetSnapshot.load() ?? (context.isPreview ? .preview : WidgetSnapshot())))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: Date(), snap: WidgetSnapshot.load() ?? WidgetSnapshot())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(3600))))
    }
}

extension WidgetSnapshot {
    static var preview: WidgetSnapshot {
        var s = WidgetSnapshot()
        s.trendWeight = 182.4; s.trendDelta30 = -1.2
        s.trendSparkline = [184.1, 183.9, 183.8, 183.5, 183.4, 183.1, 182.9, 182.8, 182.6, 182.4]
        s.nextRoutineName = "Pull Day"; s.nextRoutineExercises = 6
        s.weekLabel = "Nov 17 – 23"; s.liftingDone = 3; s.runDistance = 11.2
        return s
    }
}

private func fmt(_ v: Double, _ d: Int = 1) -> String { String(format: "%.\(d)f", v) }

struct WidgetSparkline: Shape {
    var values: [Double]
    func path(in r: CGRect) -> Path {
        var p = Path()
        guard values.count > 1, let lo = values.min(), let hi = values.max() else { return p }
        let span = max(0.001, hi - lo)
        for (i, v) in values.enumerated() {
            let pt = CGPoint(x: r.minX + r.width * CGFloat(i) / CGFloat(values.count - 1), y: r.maxY - r.height * CGFloat((v - lo) / span))
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        return p
    }
}

// MARK: Small · trend weight
struct TrendWeightWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TrendWeight", provider: SnapshotProvider()) { e in
            VStack(alignment: .leading, spacing: 2) {
                Text("Trend weight").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.secondary)
                if let w = e.snap.trendWeight {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(fmt(w)).font(.system(size: 30, weight: .bold)).minimumScaleFactor(0.7)
                        Text(e.snap.unit).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.secondary)
                    }
                    if let d = e.snap.trendDelta30 {
                        Text("\(d >= 0 ? "+" : "−")\(fmt(abs(d))) in 30d").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.cyan)
                    }
                    Spacer(minLength: 4)
                    WidgetSparkline(values: e.snap.trendSparkline).stroke(Palette.cyan, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        .frame(height: 30)
                } else {
                    Spacer()
                    Text("Connect Apple Health in the app").font(.system(size: 13)).foregroundStyle(Palette.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(Palette.card, for: .widget)
            .widgetURL(URL(string: "liftrunbody://body"))
        }
        .configurationDisplayName("Trend weight")
        .description("Your smoothed Renpho weight and 30-day change.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: Small · next up
struct NextUpWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextUp", provider: SnapshotProvider()) { e in
            VStack(alignment: .leading, spacing: 2) {
                Text("NEXT UP").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.orange)
                Text(e.snap.nextRoutineName ?? "First workout").font(.system(size: 22, weight: .bold)).minimumScaleFactor(0.7).lineLimit(2)
                Text(e.snap.nextRoutineName == nil ? "Pick a starter routine" : "\(e.snap.nextRoutineExercises) exercises")
                    .font(.system(size: 13)).foregroundStyle(Palette.secondary)
                Spacer(minLength: 4)
                Text("Start").font(.system(size: 15, weight: .semibold)).foregroundStyle(.black)
                    .frame(maxWidth: .infinity).frame(height: 34).background(Palette.orange, in: Capsule())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(Palette.card, for: .widget)
            .widgetURL(URL(string: e.snap.nextRoutineID.map { "liftrunbody://start/\($0)" } ?? "liftrunbody://today"))
        }
        .configurationDisplayName("Next up")
        .description("The next routine in your rotation.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: Medium · this week
struct ThisWeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ThisWeek", provider: SnapshotProvider()) { e in
            let s = e.snap
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("This week").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text(s.weekLabel).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                }
                bar("Lifting", "\(s.liftingDone)", "/ \(s.liftingGoal)", Double(s.liftingDone) / Double(max(1, s.liftingGoal)), Palette.orange)
                bar("Running", fmt(s.runDistance), "/ \(Int(s.runGoal)) \(s.distanceUnit)", s.runDistance / max(1, s.runGoal), Palette.cyan)
            }
            .containerBackground(Palette.card, for: .widget)
            .widgetURL(URL(string: "liftrunbody://today"))
        }
        .configurationDisplayName("This week")
        .description("Lifting sessions and running distance against your weekly goals.")
        .supportedFamilies([.systemMedium])
    }

    private func bar(_ label: String, _ v: String, _ goal: String, _ p: Double, _ c: Color) -> some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(.system(size: 14))
                Spacer()
                Text(v).font(.system(size: 15, weight: .semibold)) + Text(" \(goal)").font(.system(size: 13)).foregroundColor(Palette.secondary)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.fieldHigh)
                    Capsule().fill(c).frame(width: g.size.width * min(1, max(0.02, p)))
                }
            }
            .frame(height: 7)
        }
    }
}

// MARK: Live Activity · rest timer
struct RestTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestActivityAttributes.self) { context in
            LockScreenRestView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.75))
                .activitySystemActionForegroundColor(Palette.orange)
                .widgetURL(URL(string: "liftrunbody://workout"))
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.restEndsAt != nil ? "REST" : "LIFTING").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.orange)
                        timer(s, size: 30)
                    }
                    .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if s.restEndsAt != nil {
                        HStack(spacing: 6) {
                            Button(intent: AddRestTimeIntent()) { Text("+15").font(.system(size: 15, weight: .semibold)).lineLimit(1).fixedSize() }
                                .tint(Palette.fieldHigh)
                            Button(intent: SkipRestIntent()) { Text("Skip").font(.system(size: 15, weight: .semibold)).foregroundStyle(.black).lineLimit(1).fixedSize() }
                                .tint(Palette.orange)
                        }
                        .buttonStyle(.borderedProminent)
                        .fixedSize()
                        .buttonBorderShape(.capsule)
                        .padding(.top, 8)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let end = s.restEndsAt, let start = s.restStartedAt {
                            ProgressView(timerInterval: start...end, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                                .tint(Palette.orange)
                        }
                        Text("Next: \(s.exerciseName)\(s.upNext.isEmpty ? "" : " · \(s.upNext)")\(s.target.isEmpty ? "" : " · \(s.target)")")
                            .font(.system(size: 13)).foregroundStyle(Palette.secondary).lineLimit(1)
                    }
                    .padding(.horizontal, 6)
                }
            } compactLeading: {
                Image(systemName: "dumbbell.fill").foregroundStyle(Palette.orange)
            } compactTrailing: {
                timer(s, size: 14).frame(maxWidth: 46)
            } minimal: {
                Image(systemName: "dumbbell.fill").foregroundStyle(Palette.orange)
            }
            .keylineTint(Palette.orange)
            .widgetURL(URL(string: "liftrunbody://workout"))
        }
    }

    @ViewBuilder private func timer(_ s: RestActivityAttributes.ContentState, size: CGFloat) -> some View {
        if let end = s.restEndsAt, end > Date() {
            Text(timerInterval: Date()...end, countsDown: true).font(.system(size: size, weight: .bold)).monospacedDigit().foregroundStyle(Palette.orange)
        } else {
            Text("Go").font(.system(size: size, weight: .bold)).foregroundStyle(Palette.orange)
        }
    }
}

struct LockScreenRestView: View {
    let context: ActivityViewContext<RestActivityAttributes>
    var body: some View {
        let s = context.state
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "dumbbell.fill").foregroundStyle(Palette.orange)
                Text(context.attributes.workoutName).font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(timerInterval: context.attributes.workoutStartedAt...Date.distantFuture, countsDown: false)
                    .font(.system(size: 13)).foregroundStyle(Palette.secondary).monospacedDigit().multilineTextAlignment(.trailing).frame(width: 60)
            }
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(s.restEndsAt != nil ? "REST" : "UP NEXT").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.secondary)
                    if let end = s.restEndsAt, end > Date() {
                        Text(timerInterval: Date()...end, countsDown: true).font(.system(size: 40, weight: .bold)).monospacedDigit().foregroundStyle(Palette.orange)
                    } else {
                        Text(s.target.isEmpty ? "Go" : s.target).font(.system(size: 28, weight: .bold)).foregroundStyle(Palette.orange)
                    }
                }
                Spacer()
                if s.restEndsAt != nil {
                    Button(intent: AddRestTimeIntent()) { Text("+15").font(.system(size: 15, weight: .semibold)).frame(width: 44) }
                        .tint(.white.opacity(0.2))
                    Button(intent: SkipRestIntent()) { Text("Skip").font(.system(size: 15, weight: .semibold)).foregroundStyle(.black).frame(width: 44) }
                        .tint(Palette.orange)
                }
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            if let end = s.restEndsAt, let start = s.restStartedAt {
                ProgressView(timerInterval: start...end, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }.tint(Palette.orange)
            }
            Text("Next: \(s.exerciseName)\(s.upNext.isEmpty ? "" : " · \(s.upNext)")\(s.target.isEmpty ? "" : " · \(s.target)")")
                .font(.system(size: 13)).foregroundStyle(Palette.secondary).lineLimit(1)
        }
        .padding(16)
        .foregroundStyle(.white)
    }
}
