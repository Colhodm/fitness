import Charts
import SwiftData
import SwiftUI

struct BodyView: View {
    @EnvironmentObject var health: HealthStore
    @EnvironmentObject var settings: AppSettings
    @Environment(\.modelContext) private var context
    @State private var range: ChartRange = .m1
    @State private var logging = false

    private var staleDays: Int? {
        guard let last = health.latestHealthWeight else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: last.date), to: Calendar.current.startOfDay(for: Date())).day ?? 0
        return days >= 3 ? days : nil
    }

    var body: some View {
        let points = BodyMath.trend(health.weights)
        Screen {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Body").font(.system(size: 34, weight: .bold))
                    if let s = health.latestHealthWeight, staleDays == nil {
                        HStack(spacing: 6) {
                            Circle().fill(Palette.cyan).frame(width: 7, height: 7)
                            Text("Synced from \(s.source) via Apple Health · \(Fmt.time(s.date))").font(.system(size: 13)).foregroundStyle(Palette.secondary)
                        }
                    }
                }
                Spacer()
                CircleIconButton(system: "plus", tint: Palette.cyan) { logging = true }
            }
            .padding(.top, 8)
            if !health.isConnected && points.isEmpty {
                NoticeCard(icon: "heart.text.square", tint: Palette.cyan, title: "Connect Apple Health",
                           message: "Renpho writes weight, body fat and lean mass to Apple Health. Connect to see your trend here, or log weight manually.",
                           actionTitle: "Connect Apple Health") { Task { await health.requestAccess() } }
            }
            if let staleDays, let last = health.latestHealthWeight { staleCard(days: staleDays, last: last) }
            if points.isEmpty {
                if health.isConnected {
                    NoticeCard(icon: "scalemass", tint: Palette.cyan, title: "No weigh-ins yet",
                               message: "Step on your Renpho scale with the Renpho app open, or log weight manually.",
                               actionTitle: "Log weight manually") { logging = true }
                }
            } else {
                trendCard(points, stale: staleDays != nil)
                if staleDays == nil {
                    compositionGrid(points)
                    recentList
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $logging) { LogWeightSheet().presentationDetents([.height(300)]) }
    }

    private func staleCard(days: Int, last: BodySample) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.yellow).font(.system(size: 17))
                VStack(alignment: .leading, spacing: 4) {
                    Text("No \(last.source) weigh-in for \(days) days").font(.system(size: 17, weight: .semibold))
                    Text("The last one arrived \(Fmt.date(last.date, "EEE")), \(Fmt.time(last.date)). If you've weighed in since, \(last.source) may have stopped sending to Apple Health.")
                        .font(.system(size: 15)).foregroundStyle(Color(hex: 0xEBEBF5, opacity: 0.8)).fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(["Open the \(last.source) app and check you're signed in.",
                               "In the Health app: profile › Apps › \(last.source) Health › Turn On All.",
                               "Step on the scale with \(last.source) open."].enumerated()), id: \.offset) { i, s in
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(i + 1).").monospacedDigit()
                        Text(s).fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.system(size: 15))
                }
            }
            .padding(.leading, 28)
            HStack(spacing: 8) {
                Button { Task { await health.refresh() } } label: {
                    Text("Check again").font(.system(size: 15, weight: .semibold)).foregroundStyle(.black)
                        .frame(maxWidth: .infinity).frame(height: 40).background(Palette.yellow, in: Capsule())
                }
                Button { logging = true } label: {
                    Text("Log weight manually").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 40).background(Palette.fieldHigh, in: Capsule())
                }
            }
            .buttonStyle(.plain).padding(.top, 4)
        }
        .padding(16)
        .background(Palette.yellow.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.yellow.opacity(0.45), lineWidth: 1))
    }

    private func trendCard(_ all: [TrendPoint], stale: Bool) -> some View {
        let start = range.start() ?? .distantPast
        let pts = all.filter { $0.date >= start }
        let last = all.last!
        let today = health.weights.last { Calendar.current.isDateInToday($0.date) }
        let goal = settings.goalWeight > 0 ? Units.display(settings.goalWeight) : nil
        let values = pts.flatMap { [Units.display($0.raw), Units.display($0.trend)] }
        let lo = min(values.min() ?? 0, goal ?? .infinity), hi = values.max() ?? 1
        return Card {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(stale ? "Trend weight · as of \(Fmt.date(last.date, "EEE"))" : "Trend weight").font(.system(size: 13)).foregroundStyle(Palette.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(Fmt.fixed(Units.display(last.trend), 1)).font(.system(size: 34, weight: .bold)).monospacedDigit()
                            .foregroundStyle(stale ? Color(hex: 0xD1D1D6) : .white)
                        Text(Units.unitLabel).font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.secondary)
                    }
                    if let today, !stale {
                        Text("Today's weigh-in: \(Fmt.fixed(Units.display(today.value), 1)) \(Units.unitLabel)").font(.system(size: 13)).foregroundStyle(Palette.secondary)
                    }
                }
                Spacer()
                if !stale {
                    HStack(spacing: 2) {
                        ForEach([ChartRange.m1, .m3, .y1]) { r in
                            Button(r.rawValue) { range = r }
                                .font(.system(size: 13, weight: range == r ? .semibold : .regular))
                                .foregroundStyle(range == r ? .white : Palette.secondary)
                                .frame(width: 34, height: 26).background(range == r ? Palette.fieldHigh : .clear, in: Capsule())
                        }
                    }
                }
            }
            Chart {
                ForEach(pts) { p in
                    PointMark(x: .value("Day", p.date), y: .value("Weigh-in", Units.display(p.raw)))
                        .foregroundStyle(Palette.secondary.opacity(0.7)).symbolSize(range == .m1 ? 16 : 6)
                }
                ForEach(pts) { p in
                    LineMark(x: .value("Day", p.date), y: .value("Trend", Units.display(p.trend)), series: .value("s", "trend"))
                        .foregroundStyle(Palette.cyan).lineStyle(StrokeStyle(lineWidth: 2.5)).interpolationMethod(.monotone)
                }
                if !stale, let p = pts.last {
                    PointMark(x: .value("Day", p.date), y: .value("Trend", Units.display(p.trend))).foregroundStyle(.white).symbolSize(50)
                }
                if let goal, !stale {
                    RuleMark(y: .value("Goal", goal)).foregroundStyle(Palette.cyan.opacity(0.7)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("Goal \(Fmt.num(goal))").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.cyan)
                        }
                }
                if stale {
                    RectangleMark(xStart: .value("s", last.date.addingTimeInterval(86400 / 2)), xEnd: .value("e", Date()),
                                  yStart: .value("lo", lo - 1), yEnd: .value("hi", hi + 1))
                        .foregroundStyle(Palette.yellow.opacity(0.08))
                        .annotation(position: .overlay) {
                            Text("No data").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.yellow)
                        }
                }
            }
            .chartYScale(domain: (lo - 1)...(hi + 1))
            .chartXScale(domain: (pts.first?.date ?? start)...Date())
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
            .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { AxisGridLine().foregroundStyle(Palette.separator); AxisValueLabel() } }
            .frame(height: 190).padding(.top, 12)
            if !stale {
                HStack(spacing: 16) {
                    HStack(spacing: 6) { Capsule().fill(Palette.cyan).frame(width: 14, height: 3); Text("10-day trend") }
                    HStack(spacing: 6) { Circle().fill(Palette.secondary).frame(width: 6, height: 6); Text("Daily weigh-in") }
                }
                .font(.system(size: 12)).foregroundStyle(Palette.secondary).padding(.top, 10)
            }
        }
    }

    private func compositionGrid(_ points: [TrendPoint]) -> some View {
        let fat = health.bodyFat.last
        let lean = health.lean.last
        let rate = BodyMath.ratePerWeek(points)
        let current = points.last?.trend ?? 0
        let eta = (settings.goalWeight > 0 && rate != nil) ? BodyMath.eta(current: current, goal: settings.goalWeight, ratePerWeek: rate!) : nil
        let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible())]
        return LazyVGrid(columns: cols, spacing: 10) {
            tile("Body fat", fat.map { Fmt.fixed($0.value * 100, 1) + "%" } ?? "–",
                 BodyMath.seriesChange(health.bodyFat, days: 90).map { "\(Fmt.signed($0 * 100)) over 90 days" } ?? "Not measured", accent: true)
            tile("Lean mass", lean.map { Fmt.wu($0.value) } ?? "–",
                 BodyMath.seriesChange(health.lean, days: 90).map { "\(Fmt.signed(Units.display($0))) over 90 days" } ?? "Not measured", accent: true)
            tile("Rate", rate.map { "\(Fmt.signed(Units.display($0))) \(Units.unitLabel)/wk" } ?? "–",
                 "Goal: \(Fmt.signed(Units.display(settings.goalRate))) \(Units.unitLabel)/wk", accent: false)
            tile(settings.goalWeight > 0 ? "Goal \(Fmt.wu(settings.goalWeight))" : "Goal", settings.goalWeight > 0 ? (eta.map { etaText($0) } ?? "Not on pace") : "Set a goal",
                 settings.goalWeight > 0 ? (eta == nil ? "at current rate" : "at current rate") : "in Settings", accent: false)
        }
    }

    private func etaText(_ d: Date) -> String {
        let day = Calendar.current.component(.day, from: d)
        let part = day <= 10 ? "Early" : (day <= 20 ? "Mid" : "Late")
        return "\(part) \(Fmt.date(d, "MMM"))"
    }

    private func tile(_ label: String, _ value: String, _ sub: String, accent: Bool) -> some View {
        Card(padding: 14) {
            Text(label).font(.system(size: 13)).foregroundStyle(Palette.secondary)
            Text(value).font(.system(size: 22, weight: .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7).padding(.top, 2)
            Text(sub).font(.system(size: 12)).foregroundStyle(accent ? Palette.cyan : Palette.secondary).padding(.top, 2)
        }
    }

    private var recentList: some View {
        Card(padding: 0) {
            ForEach(Array(health.weights.suffix(5).reversed().enumerated()), id: \.element.id) { i, s in
                if i > 0 { RowDivider(inset: 16) }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Fmt.relativeDay(s.date)), \(Fmt.time(s.date))").font(.system(size: 17))
                        Text(s.source).font(.system(size: 13)).foregroundStyle(Palette.secondary)
                    }
                    Spacer()
                    Text("\(Fmt.fixed(Units.display(s.value), 1)) \(Units.unitLabel)").font(.system(size: 17, weight: .bold)).monospacedDigit()
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }
        }
    }
}

struct LogWeightSheet: View {
    @EnvironmentObject var health: HealthStore
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var date = Date()
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    TextField(health.weights.last.map { Fmt.fixed(Units.display($0.value), 1) } ?? "0.0", text: $text)
                        .keyboardType(.decimalPad).focused($focused)
                        .font(.system(size: 44, weight: .bold)).multilineTextAlignment(.trailing)
                    Text(Units.unitLabel).font(.system(size: 22, weight: .semibold)).foregroundStyle(Palette.secondary)
                }
                DatePicker("Time", selection: $date, in: ...Date()).tint(Palette.cyan)
                PrimaryButton(title: "Save", tint: Palette.cyan) { save() }.disabled(Double(text) == nil)
            }
            .padding(20)
            .navigationTitle("Log weight").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.tint(Palette.cyan) } }
            .onAppear { focused = true }
        }
        .preferredColorScheme(.dark)
    }

    private func save() {
        guard let v = Double(text.replacingOccurrences(of: ",", with: ".")) else { return }
        let pounds = Units.pounds(fromDisplay: v)
        let entry = ManualWeighIn(date: date, pounds: pounds, savedToHealth: false)
        context.insert(entry)
        try? context.save()
        Task {
            entry.savedToHealth = await health.saveWeight(pounds: pounds, date: date)
            try? context.save()
        }
        dismiss()
    }
}
