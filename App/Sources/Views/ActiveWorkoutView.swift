import SwiftData
import SwiftUI

struct KeypadTarget: Equatable {
    var set: SetRecord
    var field: SetField
    static func == (a: KeypadTarget, b: KeypadTarget) -> Bool { a.set === b.set && a.field == b.field }
}

enum SetField: String { case weight, reps, time, distance }

struct ActiveWorkoutView: View {
    @EnvironmentObject var session: WorkoutSession
    @EnvironmentObject var rest: RestTimer
    @State private var keypad: KeypadTarget?
    @State private var addingExercise = false
    @State private var confirmFinish = false

    var body: some View {
        Group {
            if let summary = session.summary {
                WorkoutSummaryView(workout: summary)
            } else if let w = session.workout {
                content(w)
            } else {
                Color.black.onAppear { session.isPresented = false }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func content(_ w: Workout) -> some View {
        let _ = session.revision
        return ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        header(w)
                        ForEach(w.sortedEntries) { entry in
                            EntryCard(entry: entry, keypad: $keypad).id(entry.persistentModelID)
                        }
                        Button { addingExercise = true } label: {
                            Label("Add exercise", systemImage: "plus").font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.orange)
                                .frame(maxWidth: .infinity).frame(height: 50).background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        Button("Discard workout", role: .destructive) { session.discard() }
                            .font(.system(size: 15)).frame(maxWidth: .infinity).padding(.top, 8)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, keypad != nil ? 420 : (rest.isRunning ? 130 : 40))
                }
                .scrollIndicators(.hidden)
                .clipped() // keep scrolled cards out from behind the status bar
                #if DEBUG
                .onAppear {
                    if ProcessInfo.processInfo.arguments.contains("-keypad"),
                       let set = session.workout?.sortedEntries.flatMap(\.sortedSets).first(where: { !$0.done }) {
                        keypad = KeypadTarget(set: set, field: .weight)
                    }
                }
                #endif
                .onChange(of: keypad) { _, k in
                    if let id = k?.set.entry?.persistentModelID { withAnimation { proxy.scrollTo(id, anchor: .top) } }
                }
            }
            if let k = keypad {
                SetKeypad(target: k, onClose: { keypad = nil }, onChange: { keypad = $0 })
                    .transition(.move(edge: .bottom))
            } else if rest.isRunning {
                RestBar().padding(.horizontal, 12).padding(.bottom, 4).transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: keypad)
        .animation(.snappy(duration: 0.25), value: rest.isRunning)
        .background(Color.black.ignoresSafeArea())
        .sheet(isPresented: $addingExercise) { ExercisePicker { session.addExercise($0) } }
        .confirmationDialog("Finish workout?", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("Finish") { Task { await session.finish() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            let open = w.entries.flatMap(\.sets).filter { !$0.done }.count
            Text(open > 0 ? "\(open) unlogged set\(open == 1 ? "" : "s") will be dropped." : "Nice work.")
        }
    }

    private func header(_ w: Workout) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button { session.isPresented = false } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "figure.strengthtraining.traditional").foregroundStyle(Palette.orange)
                        Text(w.startedAt, style: .timer).monospacedDigit()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 12).frame(height: 32).background(Palette.card, in: Capsule())
                }
                .buttonStyle(.plain)
                Spacer()
                Button { confirmFinish = true } label: {
                    Text("Finish").font(.system(size: 17, weight: .semibold)).foregroundStyle(.black)
                        .padding(.horizontal, 18).frame(height: 34).background(Palette.orange, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 8)
            Text(w.name).font(.system(size: 34, weight: .bold)).padding(.top, 10)
            Text(w.entries.isEmpty ? "Add your first exercise" : "Exercise \(session.currentIndex) of \(w.entries.count) · \(session.setsDone) sets done")
                .font(.system(size: 15)).foregroundStyle(Palette.secondary)
        }
        .padding(.bottom, 4)
    }
}

struct EntryCard: View {
    @EnvironmentObject var session: WorkoutSession
    let entry: WorkoutEntry
    @Binding var keypad: KeypadTarget?

    private var ex: Exercise { entry.exercise! }
    private var isExpanded: Bool { session.expanded == entry.persistentModelID }

    var body: some View {
        if entry.exercise == nil { EmptyView() } else if isExpanded { expanded } else { collapsed }
    }

    private var supersetLabel: String? {
        guard entry.supersetGroup != 0, let w = entry.workout else { return nil }
        let group = w.sortedEntries.filter { $0.supersetGroup == entry.supersetGroup }
        guard let i = group.firstIndex(where: { $0 === entry }) else { return nil }
        return "Superset \(Character(UnicodeScalar(64 + entry.supersetGroup)!))\(i + 1)"
    }

    private var collapsed: some View {
        let done = entry.doneWorkingSets.count
        let last = session.priorSessions(entry).last
        return Button { session.expanded = entry.persistentModelID } label: {
            Card {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        if let s = supersetLabel { Text(s.uppercased()).font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.cyan) }
                        Text(ex.name).font(.system(size: 20, weight: .semibold)).foregroundStyle(done == entry.workingSets.count && done > 0 ? Palette.secondary : .white)
                        Text("\(ex.equipmentLabel) · \(ex.kind.activeLabel)").font(.system(size: 13)).foregroundStyle(Palette.secondary)
                    }
                    Spacer()
                    Text("\(done) / \(entry.workingSets.count)").font(.system(size: 13)).foregroundStyle(done > 0 ? Palette.orange : Palette.secondary).monospacedDigit()
                }
                HStack(spacing: 6) {
                    Text(targetShort)
                    if let last {
                        Text("·")
                        Text("Last: ") + Text(last.sets.map { lastText($0) }.joined(separator: ", ")).foregroundColor(.white).fontWeight(.medium)
                    }
                }
                .font(.system(size: 13)).foregroundStyle(Palette.secondary).padding(.top, 8).lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    private func lastText(_ s: SetRecord) -> String {
        ex.kind == .bodyweight && s.weight == 0 ? "\(s.reps)" : Analytics.setText(s, ex.kind)
    }

    private var targetShort: String {
        switch ex.kind {
        case .timed: "Target \(entry.workingSets.count) × \(Fmt.clock(entry.targetSeconds))"
        case .distanceWeight: "Target \(entry.workingSets.count) × \(Fmt.dist(entry.targetDistance)) \(Units.distanceLabel)"
        default: "Target \(entry.workingSets.count) × \(entry.repLow)–\(entry.repHigh)"
        }
    }

    private var targetLine: (String, String) {
        let p = session.plan(entry)
        let inc = entry.increment
        switch ex.kind {
        case .weightReps, .assisted, .bodyweight:
            let wpart: String = switch ex.kind {
            case .weightReps: "\(Fmt.wu(p.weight)) × "
            case .assisted: "−\(Fmt.wu(p.weight)) × "
            default: p.weight > 0 ? "+\(Fmt.wu(p.weight)) × " : ""
            }
            let title = "Target \(wpart)\(entry.repLow)–\(entry.repHigh) reps"
            let next = ex.kind == .assisted ? max(0, p.weight - inc) : p.weight + inc
            let nextText = ex.kind == .bodyweight && p.weight == 0 ? "adds \(Fmt.wu(inc))" : "starts at \(Fmt.w(next))"
            let sub = p.progressed ? "Up \(Fmt.wu(inc)) from \(Fmt.w(p.lastWeight)) · you hit \(entry.repHigh)+ on every set last time"
                : "Hit \(entry.repHigh) on every set and next time \(nextText)"
            return (title, sub)
        case .timed:
            let inc = Int(entry.increment > 0 && entry.increment < 60 ? entry.increment : 10)
            return ("Target \(Fmt.clock(entry.targetSeconds)) hold" + (p.weight > 0 ? " · +\(Fmt.wu(p.weight))" : ""),
                    p.progressed ? "Up \(inc) s · you held the target on every set last time" : "Hold it on every set and next time adds \(inc) s")
        case .distanceWeight:
            return ("Target \(Fmt.wu(p.weight)) × \(Fmt.dist(entry.targetDistance)) \(Units.distanceLabel)",
                    p.progressed ? "Up \(Fmt.wu(inc)) · you covered the distance on every set last time" : "Cover the full distance on every set and next time adds \(Fmt.wu(inc))")
        }
    }

    private var columns: (String, String) {
        let u = Units.unitLabel.uppercased()
        return switch ex.kind {
        case .weightReps: (u, "REPS")
        case .bodyweight: ("+\(u)", "REPS")
        case .assisted: ("−\(u)", "REPS")
        case .timed: ("+\(u)", "TIME")
        case .distanceWeight: (u, Units.distanceLabel.uppercased())
        }
    }

    private var expanded: some View {
        let pr = session.pr(entry)
        let t = targetLine
        return Card {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    if let s = supersetLabel { Text(s.uppercased()).font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.cyan) }
                    Text(ex.name).font(.system(size: 20, weight: .semibold)).foregroundStyle(Palette.orange)
                    HStack(spacing: 6) {
                        Text("\(ex.equipmentLabel) · \(ex.muscles.first?.title ?? ex.kind.title)").foregroundStyle(Palette.secondary)
                        if let pr {
                            Text("PR").font(.system(size: 11, weight: .heavy)).foregroundStyle(.black).padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Palette.orange, in: RoundedRectangle(cornerRadius: 4))
                            Text("\(pr.value) on set \(pr.setIndex + 1)").foregroundStyle(Palette.secondary)
                        }
                    }
                    .font(.system(size: 13))
                }
                Spacer()
                menu
            }
            HStack(spacing: 10) {
                Image(systemName: "scope").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text(t.0).font(.system(size: 15, weight: .semibold))
                    Text(t.1).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(10).background(Palette.field, in: RoundedRectangle(cornerRadius: 10)).padding(.top, 10)

            HStack(spacing: 8) {
                Text("SET").frame(width: 30, alignment: .leading)
                Text("PREVIOUS").frame(maxWidth: .infinity, alignment: .leading)
                Text(columns.0).frame(width: 64)
                Text(columns.1).frame(width: 64)
                Color.clear.frame(width: 34, height: 1)
            }
            .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.secondary).padding(.top, 12).padding(.bottom, 4)

            let working = entry.workingSets
            ForEach(entry.sortedSets) { set in
                SetRow(set: set, label: set.isWarmup ? "W" : "\((working.firstIndex { $0 === set } ?? 0) + 1)",
                       kind: ex.kind, previous: session.previousSet(set, in: entry), keypad: $keypad)
                    .contextMenu {
                        Button("Delete set", systemImage: "trash", role: .destructive) { session.delete(set) }
                    }
            }
            Text("Pre-filled from your last set · swipe right or tap ✓ to log · tap a number to change it")
                .font(.system(size: 12)).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity).padding(.top, 8)
            Button { session.addSet(to: entry) } label: {
                Text("+ Add set").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 44).background(Palette.field, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain).padding(.top, 10)
        }
    }

    private var menu: some View {
        Menu {
            Button("Add warm-up set", systemImage: "flame") { session.addSet(to: entry, warmup: true) }
            Button("Move up", systemImage: "arrow.up") { session.move(entry, by: -1) }
            Button("Move down", systemImage: "arrow.down") { session.move(entry, by: 1) }
            if let w = entry.workout, let prev = w.sortedEntries.last(where: { $0.order < entry.order }) {
                if entry.supersetGroup == 0 {
                    Button("Superset with \(prev.exercise?.name ?? "previous")", systemImage: "link") {
                        let g = prev.supersetGroup != 0 ? prev.supersetGroup : (w.entries.map(\.supersetGroup).max() ?? 0) + 1
                        prev.supersetGroup = g; entry.supersetGroup = g; session.save(); session.pushLiveActivity()
                    }
                }
            }
            if entry.supersetGroup != 0 {
                Button("Remove from superset", systemImage: "link.badge.plus") { entry.supersetGroup = 0; session.save(); session.pushLiveActivity() }
            }
            Divider()
            Button("Remove exercise", systemImage: "trash", role: .destructive) { session.remove(entry) }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                .frame(width: 32, height: 32).background(Palette.field, in: Circle())
        }
    }
}

struct SetRow: View {
    @EnvironmentObject var session: WorkoutSession
    @Bindable var set: SetRecord
    let label: String
    let kind: ExerciseKind
    let previous: SetRecord?
    @Binding var keypad: KeypadTarget?
    @State private var drag: CGFloat = 0

    var body: some View {
        let fields = SetKeypad.fields(for: kind)
        HStack(spacing: 8) {
            Text(label).font(.system(size: 15, weight: .semibold)).frame(width: 30, alignment: .leading)
            Text(previous.map { kind == .bodyweight && $0.weight == 0 ? "\($0.reps)" : Analytics.setText($0, kind) } ?? "–")
                .font(.system(size: 15)).foregroundStyle(Palette.secondary).frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
            valueBox(fields.0)
            valueBox(fields.1)
            Button { session.toggle(set); if keypad?.set === set { keypad = nil } } label: {
                Image(systemName: "checkmark").font(.system(size: 14, weight: .bold))
                    .foregroundStyle(set.done ? .black : Palette.secondary)
                    .frame(width: 34, height: 32)
                    .background(set.done ? Palette.orange : Palette.fieldHigh, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6).padding(.vertical, 5)
        .background(set.done ? Palette.orange.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, -6)
        .offset(x: drag)
        .gesture(DragGesture(minimumDistance: 20).onChanged { g in drag = max(0, min(80, g.translation.width)) }
            .onEnded { g in
                if g.translation.width > 60 && !set.done { session.log(set); keypad = nil }
                withAnimation(.snappy) { drag = 0 }
            })
    }

    private func valueBox(_ f: SetField) -> some View {
        let active = keypad?.set === set && keypad?.field == f
        return Button { keypad = KeypadTarget(set: set, field: f) } label: {
            Text(SetKeypad.text(set, f, kind)).font(.system(size: 17, weight: .semibold)).monospacedDigit()
                .foregroundStyle(set.done || set.edited || active ? .white : Palette.secondary)
                .frame(width: 64, height: 34)
                .background(set.done ? Palette.fieldHigh.opacity(0.6) : Palette.field, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(active ? Palette.orange : (set.done ? .clear : Palette.fieldHigh), lineWidth: active ? 2 : 1))
        }
        .buttonStyle(.plain)
    }
}

struct RestBar: View {
    @EnvironmentObject var rest: RestTimer
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text("REST").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.secondary)
                    Text(Fmt.clock(Int(rest.remaining.rounded(.up)))).font(.system(size: 34, weight: .bold)).monospacedDigit()
                }
                Spacer()
                pill("−15") { rest.add(-15) }
                pill("+15") { rest.add(15) }
                Button { rest.skip() } label: {
                    Text("Skip").font(.system(size: 17, weight: .semibold)).foregroundStyle(.black)
                        .frame(width: 64, height: 44).background(Palette.orange, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            ProgressBar(value: rest.progress, tint: Palette.orange, height: 6)
        }
        .padding(16)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.6), radius: 20, y: -4)
    }
    private func pill(_ t: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Text(t).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 56, height: 44).background(Palette.fieldHigh, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct ExercisePicker: View {
    let onPick: (Exercise) -> Void
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var search = ""
    @State private var creating = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(exercises.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.aliases.contains { $0.localizedCaseInsensitiveContains(search) } }) { ex in
                    Button { onPick(ex); dismiss() } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ex.name).foregroundStyle(.white)
                            Text("\(ex.equipmentLabel) · \(ex.kind.listLabel)").font(.system(size: 13)).foregroundStyle(Palette.secondary)
                        }
                    }
                    .listRowBackground(Palette.card)
                }
                Button("New exercise…") { creating = true }.foregroundStyle(Palette.orange).listRowBackground(Palette.card)
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always))
            .screenBackground()
            .navigationTitle("Add exercise").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.tint(Palette.orange) } }
            .navigationDestination(isPresented: $creating) {
                ExerciseEditorView(onSave: { onPick($0); dismiss() })
            }
        }
        .preferredColorScheme(.dark)
    }
}
