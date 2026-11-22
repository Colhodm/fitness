import SwiftData
import SwiftUI

struct WorkoutSummaryView: View {
    @EnvironmentObject var session: WorkoutSession
    let workout: Workout
    @State private var routineUpdated = false
    @State private var naming = false
    @State private var routineName = ""

    private struct NextRow: Identifiable { let id = UUID(); let name: String; let reason: String; let change: String; let up: Bool }

    private var nextRows: [NextRow] {
        workout.sortedEntries.compactMap { e -> NextRow? in
            guard let ex = e.exercise, !e.doneWorkingSets.isEmpty else { return nil }
            let p = Analytics.plan(kind: ex.kind, config: ProgressionConfig(e), last: Session(entry: e, workout: workout, sets: e.doneWorkingSets))
            let change: String
            switch ex.kind {
            case .timed: change = p.progressed ? "\(Fmt.clock(p.lastWeight > 0 ? Int(p.lastWeight) : e.targetSeconds)) → \(Fmt.clock(p.seconds))" : "Same time"
            case .assisted: change = p.progressed ? "−\(Fmt.w(p.lastWeight)) → −\(Fmt.wu(p.weight))" : "Same assist"
            case .bodyweight: change = p.progressed ? (p.lastWeight == 0 ? "Add \(Fmt.wu(p.weight))" : "+\(Fmt.w(p.lastWeight)) → +\(Fmt.wu(p.weight))") : "Same weight"
            case .distanceWeight: change = p.progressed ? "\(Fmt.w(p.lastWeight)) → \(Fmt.wu(p.weight))" : "Same weight"
            case .weightReps: change = p.progressed ? "\(Fmt.w(p.lastWeight)) → \(Fmt.wu(p.weight))" : "Same weight"
            }
            return NextRow(name: ex.name, reason: p.reason, change: change, up: p.progressed)
        }
        .sorted { $0.up && !$1.up }
    }

    var body: some View {
        let prs = Analytics.workoutPRs(workout)
        let minutes = Int((workout.duration / 60).rounded())
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "checkmark").font(.system(size: 26, weight: .bold)).foregroundStyle(Palette.orange)
                    .frame(width: 64, height: 64).background(Palette.orange.opacity(0.18), in: Circle()).padding(.top, 24)
                VStack(spacing: 4) {
                    Text("\(workout.name) done").font(.system(size: 28, weight: .bold))
                    Text("\(Fmt.date(workout.startedAt, "EEE, MMM d")) · \(minutes) min").font(.system(size: 15)).foregroundStyle(Palette.secondary)
                }
                HStack(spacing: 8) {
                    tile("Volume", Fmt.num(Units.display(workout.volume), maxDecimals: 0), Units.unitLabel, hot: false)
                    tile("Sets", "\(workout.completedSets.count)", "\(workout.entries.count) exercises", hot: false)
                    tile("PRs", "\(prs.count)", prs.count == 1 ? "new best" : "new bests", hot: !prs.isEmpty)
                }
                if !prs.isEmpty {
                    Card {
                        Text("New personal records").font(.system(size: 17, weight: .semibold)).padding(.bottom, 4)
                        ForEach(Array(prs.enumerated()), id: \.element.id) { i, pr in
                            if i > 0 { RowDivider() }
                            row(pr.exerciseName, pr.detail, pr.value, color: Palette.orange)
                        }
                    }
                }
                let rows = nextRows
                if !rows.isEmpty {
                    Card {
                        HStack {
                            Text("Next time").font(.system(size: 17, weight: .semibold))
                            Spacer()
                            Text("Pre-filled for you").font(.system(size: 13)).foregroundStyle(Palette.secondary)
                        }
                        .padding(.bottom, 4)
                        ForEach(Array(rows.prefix(5).enumerated()), id: \.element.id) { i, r in
                            if i > 0 { RowDivider() }
                            row(r.name, r.reason, r.change, color: r.up ? Palette.orange : Palette.secondary)
                        }
                    }
                }
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "heart.fill").font(.system(size: 12)).foregroundStyle(.white)
                        .frame(width: 22, height: 22).background(Color(hex: 0xFF375F), in: RoundedRectangle(cornerRadius: 5))
                    Text(workout.savedToHealth ? "Saved to Apple Health as a \(minutes)-minute strength training workout"
                         : "Not saved to Apple Health. Turn on Health access in Settings to log workouts there.")
                        .font(.system(size: 13)).foregroundStyle(Palette.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 150)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                PrimaryButton(title: "Done") { session.summary = nil; session.isPresented = false }
                if workout.routine != nil {
                    Button(routineUpdated ? "\(workout.routine!.name) routine updated" : "Update \(workout.routine!.name) routine with today's changes") {
                        session.updateRoutine(from: workout); routineUpdated = true
                    }
                    .disabled(routineUpdated)
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(routineUpdated ? Palette.secondary : Palette.orange)
                } else {
                    Button("Save as routine") { naming = true }.font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.orange)
                }
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
            .background(LinearGradient(colors: [.black.opacity(0), .black, .black], startPoint: .top, endPoint: .bottom))
        }
        .background(Color.black.ignoresSafeArea())
        .alert("Save as routine", isPresented: $naming) {
            TextField("Name", text: $routineName)
            Button("Save") { if !routineName.isEmpty { session.saveAsRoutine(workout, name: routineName) } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func tile(_ label: String, _ value: String, _ sub: String, hot: Bool) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.system(size: 13)).foregroundStyle(hot ? Palette.orange : Palette.secondary)
            Text(value).font(.system(size: 22, weight: .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(sub).font(.system(size: 12)).foregroundStyle(hot ? Palette.orange : Palette.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .background(hot ? Palette.orange.opacity(0.12) : Palette.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(hot ? Palette.orange : .clear, lineWidth: 1))
    }

    private func row(_ title: String, _ sub: String, _ value: String, color: Color) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 17))
                Text(sub).font(.system(size: 13)).foregroundStyle(Palette.secondary)
            }
            Spacer()
            Text(value).font(.system(size: 17, weight: .bold)).foregroundStyle(color).monospacedDigit()
        }
        .padding(.vertical, 8)
    }
}
