import SwiftData
import SwiftUI

struct LiftHomeView: View {
    @EnvironmentObject var session: WorkoutSession
    @EnvironmentObject var router: Router
    @Environment(\.modelContext) private var context
    @Query(sort: \Routine.order) private var routines: [Routine]
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Query(sort: \Workout.startedAt, order: .reverse) private var workouts: [Workout]
    @State private var search = ""
    @State private var filter = "All"

    private let filters = ["All", "Chest", "Back", "Legs", "Shoulders", "Arms", "Core"]
    private var finished: [Workout] { workouts.filter { $0.endedAt != nil } }

    private var filtered: [Exercise] {
        let q = NotesImporter.normalize(search)
        let list = exercises.filter { ex in
            let m = ex.muscles
            let pass: Bool = switch filter {
            case "All": true
            case "Arms": m.contains(.biceps) || m.contains(.triceps)
            case "Legs": m.contains(.legs) || m.contains(.glutes)
            default: m.contains(Muscle(rawValue: filter.lowercased()) ?? .core)
            }
            guard pass else { return false }
            if q.isEmpty { return true }
            return NotesImporter.normalize(ex.name).contains(q) || ex.aliases.contains { NotesImporter.normalize($0).contains(q) }
        }
        // Exercises you've done come first, most-used on top.
        return list.sorted { a, b in
            let ca = a.entries.count, cb = b.entries.count
            return ca == cb ? a.name < b.name : ca > cb
        }
    }

    var body: some View {
        let next = Analytics.nextRoutine(routines, workouts: finished)
        Screen {
            LargeTitle(title: "Lift", trailing: AnyView(CircleIconButton(system: "plus", tint: Palette.orange) { router.push(.newExercise) }))
            SectionHeader(title: "Routines", trailing: routines.isEmpty ? nil : "Edit") {
                router.push(.routine((next ?? routines.first)?.persistentModelID))
            }
            routinesRow(next)
            HStack(spacing: 10) {
                PrimaryButton(title: session.isActive ? "Resume workout" : "Start empty workout") {
                    session.isActive ? (session.isPresented = true) : session.start(routine: nil)
                }
                if let last = finished.first, !session.isActive {
                    Button { session.repeatLast(last) } label: {
                        Text("Repeat last").font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.orange)
                            .padding(.horizontal, 16).frame(height: 50).background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
            SectionHeader(title: "Exercises", trailing: "\(exercises.count) total").padding(.top, 8)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.secondary)
                TextField("Search exercises", text: $search).textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            .padding(.horizontal, 12).frame(height: 40)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(filters, id: \.self) { f in Chip(title: f, selected: filter == f) { filter = f } }
                }
            }
            .scrollIndicators(.hidden)
            Card(padding: 0) {
                ForEach(Array(filtered.enumerated()), id: \.element.persistentModelID) { i, ex in
                    if i > 0 { RowDivider(inset: 16) }
                    ExerciseRow(exercise: ex).onTapGesture { router.push(.exercise(ex.persistentModelID)) }
                }
                if filtered.isEmpty {
                    Button { router.push(.newExercise) } label: {
                        Text(search.isEmpty ? "No exercises" : "Create “\(search)”").foregroundStyle(Palette.orange).padding(16)
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder private func routinesRow(_ next: Routine?) -> some View {
        if routines.isEmpty {
            HStack(spacing: 8) {
                ForEach(Library.starters, id: \.name) { s in
                    Button { session.start(routine: Library.createStarter(s, in: context)) } label: {
                        routineCard(name: s.name, sub: "\(s.items.count) exercises", foot: "Starter", highlighted: false)
                    }
                    .buttonStyle(.plain)
                }
            }
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(routines) { r in
                        let isNext = r.persistentModelID == next?.persistentModelID
                        Button { session.start(routine: r) } label: {
                            routineCard(name: r.name, sub: "\(r.items.count) exercises",
                                        foot: isNext ? "Up next" : (r.lastPerformed.map { "Last: \(Fmt.relativeDay($0))" } ?? "Not done yet"),
                                        highlighted: isNext)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Edit routine", systemImage: "pencil") { router.push(.routine(r.persistentModelID)) }
                            Button("Start", systemImage: "play") { session.start(routine: r) }
                        }
                    }
                    Button { router.push(.routine(nil)) } label: {
                        Image(systemName: "plus").font(.system(size: 20, weight: .semibold)).foregroundStyle(Palette.secondary)
                            .frame(width: 60, height: 90).background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func routineCard(name: String, sub: String, foot: String, highlighted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name).font(.system(size: 17, weight: .semibold))
            Text(sub).font(.system(size: 13)).foregroundStyle(Palette.secondary)
            Text(foot).font(.system(size: 13, weight: highlighted ? .semibold : .regular))
                .foregroundStyle(highlighted ? Palette.orange : Palette.secondary)
        }
        .padding(12).frame(width: 112, height: 90, alignment: .topLeading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(highlighted ? Palette.orange : .clear, lineWidth: 1.5))
    }
}

struct ExerciseRow: View {
    let exercise: Exercise
    var body: some View {
        let sessions = Analytics.sessions(exercise)
        let values = sessions.suffix(8).map { Analytics.primary(exercise.kind, $0) }
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name).font(.system(size: 17))
                Text("\(exercise.equipmentLabel) · \(exercise.kind.listLabel)").font(.system(size: 13)).foregroundStyle(Palette.secondary)
            }
            Spacer()
            if values.count > 1 { Sparkline(values: values, tint: Palette.orange, lineWidth: 1.5).frame(width: 48, height: 18) }
            if let h = Analytics.headline(exercise, sessions) {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(h.value).font(.system(size: 17, weight: .bold)).monospacedDigit()
                    Text(h.caption).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                }
                .frame(minWidth: 70, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
