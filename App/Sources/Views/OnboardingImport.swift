import SwiftData
import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var health: HealthStore
    @State private var step = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Step \(step) of 3").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.secondary).padding(.top, 24)
            switch step {
            case 1: units
            case 2: healthStep
            default: goals
            }
            Spacer()
            PrimaryButton(title: step == 2 && !health.isConnected ? "Connect Apple Health" : (step == 3 ? "Start lifting" : "Continue"),
                          tint: step == 2 ? Palette.cyan : Palette.orange) {
                if step == 2 && !health.isConnected { Task { await health.requestAccess() } }
                else if step < 3 { step += 1 } else { settings.onboardingDone = true }
            }
            if step == 2 {
                Button(health.isConnected ? "Continue" : "Skip for now") { step = 3 }
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.cyan).frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 20).padding(.bottom, 12)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private var units: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Lift + Run + Body").font(.system(size: 34, weight: .bold))
            Text("Log lifts with pre-filled weights that go up when you've earned it. Runs and weigh-ins come in from Apple Health.")
                .font(.system(size: 17)).foregroundStyle(Palette.secondary)
            Card {
                HStack { Text("Units"); Spacer(); SegmentedPicker(options: [(WeightUnit.lb, "lb"), (WeightUnit.kg, "kg")], selection: $settings.unit).frame(width: 120) }
            }
        }
    }

    private var healthStep: some View {
        let weights = health.weights.filter { !$0.isManual }
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Connect Apple Health").font(.system(size: 34, weight: .bold))
                Text("Your Renpho scale and your runs already save to Apple Health. Connecting it means you never log either by hand.")
                    .font(.system(size: 17)).foregroundStyle(Palette.secondary)
                Card {
                    perm("scalemass.fill", "Weight and body composition", "Read · from your Renpho scale")
                    RowDivider().padding(.vertical, 8)
                    perm("figure.run", "Runs, routes and heart rate", "Read · from your watch or running app")
                    RowDivider().padding(.vertical, 8)
                    perm("dumbbell.fill", "Strength workouts", "Write · so lifts count in Apple Health")
                }
                if health.isConnected {
                    Text("WHAT WE FOUND").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.secondary)
                    Card {
                        if let last = weights.last {
                            found(true, "\(last.source) is syncing", "Last weigh-in \(Fmt.relativeDay(last.date).lowercased()), \(Fmt.time(last.date)) · \(weights.count) weigh-ins")
                        } else {
                            found(false, "No weigh-ins yet", "Renpho not showing up? Open the Health app, tap your profile, then Apps › Renpho Health › Turn On All.")
                        }
                        RowDivider().padding(.vertical, 8)
                        if let first = health.runs.last {
                            found(true, "\(health.runs.count) runs found", "From \(first.source), going back to \(Fmt.date(first.start, "MMMM"))")
                        } else {
                            found(false, "No runs yet", "Record one with the Workout app on Apple Watch.")
                        }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var goals: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Weekly goals").font(.system(size: 34, weight: .bold))
            Text("Shown on Today and the This Week widget. Change them any time in Settings.").font(.system(size: 17)).foregroundStyle(Palette.secondary)
            Card {
                Stepper("Lifting: \(settings.weeklyLiftGoal) sessions", value: $settings.weeklyLiftGoal, in: 1...7)
                RowDivider().padding(.vertical, 8)
                Stepper("Running: \(Fmt.num(settings.weeklyRunGoal)) mi", value: $settings.weeklyRunGoal, in: 0...100)
            }
        }
    }

    private func perm(_ icon: String, _ t: String, _ s: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(Palette.cyan).frame(width: 32, height: 32).background(Palette.cyan.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(t).font(.system(size: 17))
                Text(s).font(.system(size: 13)).foregroundStyle(Palette.secondary)
            }
        }
    }

    private func found(_ ok: Bool, _ t: String, _ s: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill").foregroundStyle(ok ? Color(hex: 0x30D158) : Palette.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text(t).font(.system(size: 17, weight: .semibold))
                Text(s).font(.system(size: 13)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct ImportNotesView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var text = ""
    @State private var mapping: [String: Exercise] = [:]
    @State private var imported: Int?

    private var parsed: [NotesImporter.ParsedWorkout] { NotesImporter.parse(text) }

    var body: some View {
        let workouts = parsed
        let names = orderedNames(workouts)
        let setCounts = counts(workouts)
        let total = names.filter { mapping[$0.lowercased()] != nil }.reduce(0) { $0 + (setCounts[$1.lowercased()] ?? 0) }
        Screen {
            VStack(alignment: .leading, spacing: 6) {
                Text("Bring your history").font(.system(size: 28, weight: .bold))
                Text("Paste your lifting notes as they are. Dates, \"185x5x3\" and \"12, 10, 9\" all work.").font(.system(size: 15)).foregroundStyle(Palette.secondary)
            }
            Card {
                HStack {
                    Text("PASTED FROM NOTES").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.secondary)
                    Spacer()
                    Button("Paste") { text = UIPasteboard.general.string ?? text }.font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.orange)
                }
                TextEditor(text: $text).font(.system(size: 15, design: .monospaced)).frame(minHeight: 160).scrollContentBackground(.hidden)
            }
            if !workouts.isEmpty {
                HStack {
                    Text("\(workouts.count) workout\(workouts.count == 1 ? "" : "s") · \(setCounts.values.reduce(0, +)) sets found").font(.system(size: 17, weight: .semibold))
                    Spacer()
                    if let f = workouts.map(\.date).min(), let l = workouts.map(\.date).max() {
                        Text(f == l ? Fmt.date(f, "MMM d") : "\(Fmt.date(f, "MMM d")) – \(Fmt.date(l, "MMM d"))").font(.system(size: 13)).foregroundStyle(Palette.secondary)
                    }
                }
                Card(padding: 0) {
                    ForEach(Array(names.enumerated()), id: \.element) { i, raw in
                        if i > 0 { RowDivider(inset: 16) }
                        HStack(spacing: 8) {
                            Text(raw).font(.system(size: 17)).frame(width: 80, alignment: .leading).lineLimit(1)
                            Image(systemName: "arrow.right").font(.system(size: 13)).foregroundStyle(Palette.tertiary)
                            Menu {
                                ForEach(exercises) { ex in Button(ex.name) { mapping[raw.lowercased()] = ex } }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(mapping[raw.lowercased()]?.name ?? "Pick exercise").lineLimit(1)
                                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 11))
                                }
                                .font(.system(size: 17, weight: mapping[raw.lowercased()] == nil ? .semibold : .regular))
                                .foregroundStyle(mapping[raw.lowercased()] == nil ? Palette.orange : .white)
                            }
                            Spacer()
                            Text("\(setCounts[raw.lowercased()] ?? 0) sets").font(.system(size: 13)).foregroundStyle(Palette.secondary)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                    }
                }
                Text("New names are remembered, so \"\(names.first { mapping[$0.lowercased()] == nil } ?? names.first ?? "")\" maps automatically next time.")
                    .font(.system(size: 13)).foregroundStyle(Palette.secondary)
                PrimaryButton(title: imported != nil ? "Imported \(imported!) workouts" : "Import \(total) sets") {
                    for raw in names { if let ex = mapping[raw.lowercased()] { NotesImporter.remember(alias: raw, for: ex) } }
                    imported = NotesImporter.importWorkouts(workouts, mapping: mapping, into: context)
                    WidgetSync.shared.refresh()
                }
                .disabled(total == 0 || imported != nil)
            }
            Button("Skip for now") { dismiss() }.font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.orange).frame(maxWidth: .infinity)
        }
        .navigationTitle("Import from Notes").navigationBarTitleDisplayMode(.inline)
        .onChange(of: text) { _, _ in autoMap() }
    }

    private func orderedNames(_ w: [NotesImporter.ParsedWorkout]) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for wk in w { for l in wk.lines where seen.insert(l.rawName.lowercased()).inserted { out.append(l.rawName) } }
        return out
    }

    private func counts(_ w: [NotesImporter.ParsedWorkout]) -> [String: Int] {
        var c: [String: Int] = [:]
        for wk in w { for l in wk.lines {
            let kind = mapping[l.rawName.lowercased()]?.kind ?? .weightReps
            c[l.rawName.lowercased(), default: 0] += NotesImporter.sets(l, kind: kind).count
        } }
        return c
    }

    private func autoMap() {
        imported = nil
        for raw in orderedNames(parsed) where mapping[raw.lowercased()] == nil {
            if let ex = NotesImporter.match(raw, in: exercises) { mapping[raw.lowercased()] = ex }
        }
    }
}
