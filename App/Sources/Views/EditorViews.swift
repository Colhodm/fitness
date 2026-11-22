import SwiftData
import SwiftUI

struct ExerciseEditorView: View {
    var existing: Exercise? = nil
    var onSave: ((Exercise) -> Void)? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind: ExerciseKind = .weightReps
    @State private var perSide = false
    @State private var equipment: Equipment = .barbell
    @State private var muscles: Set<Muscle> = []
    @State private var loaded = false

    var body: some View {
        Form {
            Section("Name") {
                TextField("e.g. Cable Fly", text: $name).font(.system(size: 17))
            }
            Section("Type · decides what each set logs") {
                ForEach(ExerciseKind.allCases) { k in
                    Button { kind = k } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(k.title).foregroundStyle(.white)
                                Text(k.detail).font(.system(size: 13)).foregroundStyle(Palette.secondary)
                            }
                            Spacer()
                            if kind == k { Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.orange) }
                        }
                    }
                }
            }
            Section {
                Toggle(isOn: $perSide) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Track each side separately")
                        Text("For single-arm and single-leg work").font(.system(size: 13)).foregroundStyle(Palette.secondary)
                    }
                }
                .tint(Palette.orange)
            }
            Section("Equipment") {
                FlowChips(items: Equipment.allCases.filter { $0 != .bodyweight || kind != .weightReps }, title: \.title,
                          isOn: { equipment == $0 }) { equipment = $0 }
            }
            Section("Muscles worked") {
                FlowChips(items: [.chest, .shoulders, .triceps, .back, .biceps, .legs, .glutes, .core], title: \Muscle.title,
                          isOn: { muscles.contains($0) }) { m in if muscles.contains(m) { muscles.remove(m) } else { muscles.insert(m) } }
            }
        }
        .tint(Palette.orange)
        .screenBackground()
        .navigationTitle(existing == nil ? "New Exercise" : "Edit Exercise")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.fontWeight(.semibold).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let e = existing { name = e.name; kind = e.kind; perSide = e.perSide; equipment = e.equipment; muscles = Set(e.muscles) }
        }
    }

    private func save() {
        let ordered = Muscle.allCases.filter { muscles.contains($0) }
        let ex: Exercise
        if let e = existing {
            e.name = name.trimmingCharacters(in: .whitespaces); e.kind = kind; e.perSide = perSide; e.equipment = equipment; e.muscles = ordered
            ex = e
        } else {
            ex = Exercise(name: name.trimmingCharacters(in: .whitespaces), kind: kind, equipment: equipment, muscles: ordered, perSide: perSide)
            context.insert(ex)
        }
        try? context.save()
        onSave?(ex)
        dismiss()
    }
}

struct FlowChips<T: Hashable>: View {
    let items: [T]
    let title: KeyPath<T, String>
    let isOn: (T) -> Bool
    let toggle: (T) -> Void
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
            ForEach(items, id: \.self) { i in
                Button { toggle(i) } label: {
                    Text(i[keyPath: title]).font(.system(size: 15, weight: isOn(i) ? .semibold : .regular))
                        .foregroundStyle(isOn(i) ? .black : .white)
                        .frame(maxWidth: .infinity).frame(height: 34)
                        .background(isOn(i) ? Palette.orange : Palette.field, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Editable copy of a routine item so Cancel discards changes.
struct DraftItem: Identifiable {
    let id = UUID()
    var exercise: Exercise
    var sets: Int
    var repLow: Int
    var repHigh: Int
    var rest: Int
    var increment: Double
    var superset: Int
    var seconds: Int
    var distance: Double
}

struct RoutineEditorView: View {
    let routine: Routine?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var items: [DraftItem] = []
    @State private var expanded: UUID?
    @State private var selecting = false
    @State private var picked: Set<UUID> = []
    @State private var adding = false
    @State private var loaded = false

    var body: some View {
        Screen {
            TextField("Routine name", text: $name).font(.system(size: 34, weight: .bold))
            VStack(spacing: 0) {
                ForEach(groups, id: \.first!.id) { group in
                    if group.count > 1 && group[0].superset != 0 {
                        supersetBlock(group)
                    } else {
                        row(group[0])
                    }
                    RowDivider(inset: 16)
                }
            }
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
            HStack(spacing: 10) {
                PrimaryButton(title: "+ Add exercise", tint: Palette.orange, filled: false) { adding = true }
                PrimaryButton(title: selecting ? (picked.count >= 2 ? "Group \(picked.count)" : "Pick 2+") : "Group as superset", tint: Palette.orange, filled: false) {
                    if selecting && picked.count >= 2 {
                        let g = (items.map(\.superset).max() ?? 0) + 1
                        for i in items.indices where picked.contains(items[i].id) { items[i].superset = g }
                        selecting = false; picked = []
                    } else { selecting.toggle(); picked = [] }
                }
            }
            if routine != nil {
                Button("Delete routine", role: .destructive) { if let r = routine { context.delete(r); try? context.save() }; dismiss() }
                    .frame(maxWidth: .infinity).padding(.top, 8)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Edit Routine")
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.tint(Palette.orange) }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.fontWeight(.semibold).tint(Palette.orange).disabled(name.isEmpty) }
        }
        .sheet(isPresented: $adding) {
            ExercisePicker { ex in
                let s = AppSettings.shared
                items.append(DraftItem(exercise: ex, sets: 3, repLow: ex.kind == .timed || ex.kind == .distanceWeight ? 1 : 8,
                                       repHigh: ex.kind == .timed || ex.kind == .distanceWeight ? 1 : 12, rest: s.defaultRest,
                                       increment: ex.kind == .timed ? 10 : (ex.isUpperBody ? s.upperIncrement : s.lowerIncrement), superset: 0,
                                       seconds: ex.kind == .timed ? 30 : 0, distance: ex.kind == .distanceWeight ? 40 * Units.metersPerYard : 0))
                expanded = items.last?.id
            }
        }
        .onAppear(perform: load)
    }

    private var groups: [[DraftItem]] {
        var out: [[DraftItem]] = []
        for i in items {
            if i.superset != 0, let last = out.last, last[0].superset == i.superset { out[out.count - 1].append(i) } else { out.append([i]) }
        }
        return out
    }

    private func binding(_ id: UUID) -> Binding<DraftItem> {
        Binding(get: { items.first { $0.id == id } ?? items[0] }, set: { v in if let i = items.firstIndex(where: { $0.id == id }) { items[i] = v } })
    }

    private func summary(_ d: DraftItem, rest: Bool = true) -> String {
        var parts: [String] = []
        switch d.exercise.kind {
        case .timed: parts.append("\(d.sets) × \(Fmt.clock(d.seconds))")
        case .distanceWeight: parts.append("\(d.sets) × \(Fmt.dist(d.distance)) \(Units.distanceLabel)")
        default: parts.append("\(d.sets) × \(d.repLow)–\(d.repHigh)")
        }
        if rest { parts.append("rest \(Fmt.clock(d.rest))") }
        parts.append(d.exercise.kind == .bodyweight ? "then add weight" : d.exercise.kind == .timed ? "+\(Int(d.increment)) s" : "+\(Fmt.wu(d.increment))")
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private func row(_ d: DraftItem, inSuperset: Bool = false) -> some View {
        let open = expanded == d.id
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                if selecting {
                    Image(systemName: picked.contains(d.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(Palette.orange)
                } else if !inSuperset {
                    Image(systemName: "line.3.horizontal").foregroundStyle(Palette.tertiary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.exercise.name).font(.system(size: 17, weight: open ? .semibold : .regular)).foregroundStyle(open ? Palette.orange : .white)
                    if !open { Text(summary(d, rest: !inSuperset)).font(.system(size: 13)).foregroundStyle(Palette.secondary) }
                }
                Spacer()
                Image(systemName: "chevron.down").font(.system(size: 13, weight: .semibold)).foregroundStyle(open ? Palette.orange : Palette.tertiary)
                    .rotationEffect(.degrees(open ? 0 : -90))
            }
            .padding(.horizontal, inSuperset ? 0 : 16).padding(.vertical, 12)
            .contentShape(Rectangle())
            .onTapGesture {
                if selecting { if picked.contains(d.id) { picked.remove(d.id) } else { picked.insert(d.id) } }
                else { withAnimation(.snappy) { expanded = open ? nil : d.id } }
            }
            if open { detail(binding(d.id)).padding(.horizontal, inSuperset ? 0 : 16).padding(.bottom, 14) }
        }
    }

    private func supersetBlock(_ group: [DraftItem]) -> some View {
        HStack(spacing: 12) {
            Rectangle().fill(Palette.orange).frame(width: 3)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("SUPERSET · REST \(Fmt.clock(group.map(\.rest).max() ?? 90)) AFTER BOTH").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.orange)
                    Spacer()
                    Button("Ungroup") { for i in items.indices where items[i].superset == group[0].superset { items[i].superset = 0 } }
                        .font(.system(size: 13)).foregroundStyle(Palette.secondary)
                }
                .padding(.top, 12)
                ForEach(group) { row($0, inSuperset: true) }
            }
        }
        .padding(.leading, 16).padding(.trailing, 16)
    }

    private func detail(_ d: Binding<DraftItem>) -> some View {
        let kind = d.wrappedValue.exercise.kind
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                box("Sets") {
                    HStack {
                        roundButton("minus") { d.wrappedValue.sets = max(1, d.wrappedValue.sets - 1) }
                        Text("\(d.wrappedValue.sets)").font(.system(size: 22, weight: .bold)).frame(maxWidth: .infinity)
                        roundButton("plus") { d.wrappedValue.sets = min(10, d.wrappedValue.sets + 1) }
                    }
                }
                switch kind {
                case .timed:
                    box("Target hold") { Stepper(Fmt.clock(d.wrappedValue.seconds), value: d.seconds, in: 5...600, step: 5).font(.system(size: 20, weight: .bold)) }
                case .distanceWeight:
                    box("Distance") {
                        Stepper("\(Fmt.dist(d.wrappedValue.distance)) \(Units.distanceLabel)", value: Binding(get: { Units.distanceDisplay(d.wrappedValue.distance) }, set: { d.wrappedValue.distance = Units.meters(fromDisplay: $0) }), in: 5...500, step: 5)
                            .font(.system(size: 20, weight: .bold))
                    }
                default:
                    box("Rep range") {
                        HStack(spacing: 8) {
                            numberMenu(d.repLow, 1...30)
                            Text("to").foregroundStyle(Palette.secondary)
                            numberMenu(d.repHigh, max(1, d.wrappedValue.repLow)...40)
                        }
                    }
                }
            }
            HStack(spacing: 10) {
                box("Rest between sets") {
                    Menu {
                        ForEach([30, 45, 60, 75, 90, 120, 150, 180, 240, 300], id: \.self) { s in Button(Fmt.clock(s)) { d.wrappedValue.rest = s } }
                    } label: { Text(Fmt.clock(d.wrappedValue.rest)).font(.system(size: 22, weight: .bold)).foregroundStyle(.white) }
                }
                box("Increase by") {
                    Menu {
                        ForEach(kind == .timed ? [5.0, 10, 15, 30] : [0, 2.5, 5, 10, 15, 20], id: \.self) { v in
                            Button(kind == .timed ? "+\(Int(v)) s" : "+\(Fmt.wu(v))") { d.wrappedValue.increment = v }
                        }
                    } label: {
                        Text(kind == .timed ? "+\(Int(d.wrappedValue.increment)) s" : "+\(Fmt.wu(d.wrappedValue.increment))")
                            .font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                    }
                }
            }
            Text(explanation(d.wrappedValue)).font(.system(size: 13)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Remove from routine", role: .destructive) { items.removeAll { $0.id == d.wrappedValue.id } }.font(.system(size: 15))
        }
    }

    private func explanation(_ d: DraftItem) -> String {
        switch d.exercise.kind {
        case .timed: "When every set holds \(Fmt.clock(d.seconds)), the next session adds \(Int(d.increment)) s. Otherwise the target stays the same."
        case .distanceWeight: "When every set covers \(Fmt.dist(d.distance)) \(Units.distanceLabel), the next session pre-fills \(Fmt.wu(d.increment)) heavier."
        case .assisted: "When every set reaches \(d.repHigh) reps, the next session uses \(Fmt.wu(d.increment)) less assistance."
        default: "When every set reaches \(d.repHigh) reps, the next session pre-fills \(Fmt.wu(d.increment)) heavier. Otherwise the weight stays the same."
        }
    }

    private func box<C: View>(_ label: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.system(size: 13)).foregroundStyle(Palette.secondary)
            c()
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.field, in: RoundedRectangle(cornerRadius: 12))
    }

    private func roundButton(_ icon: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Image(systemName: icon).font(.system(size: 13, weight: .bold)).foregroundStyle(.white).frame(width: 30, height: 30).background(Palette.fieldHigh, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func numberMenu(_ v: Binding<Int>, _ range: ClosedRange<Int>) -> some View {
        Menu {
            ForEach(Array(range), id: \.self) { n in Button("\(n)") { v.wrappedValue = n } }
        } label: {
            Text("\(v.wrappedValue)").font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                .frame(width: 44, height: 34).background(Palette.fieldHigh, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let r = routine else { name = "New Routine"; return }
        name = r.name.hasSuffix("Day") ? r.name : "\(r.name) Day"
        items = r.sortedItems.compactMap { i in
            i.exercise.map { DraftItem(exercise: $0, sets: i.sets, repLow: i.repLow, repHigh: i.repHigh, rest: i.restSeconds, increment: i.increment,
                                       superset: i.supersetGroup, seconds: i.targetSeconds, distance: i.targetDistance) }
        }
        expanded = items.count > 1 ? items[1].id : items.first?.id
    }

    private func save() {
        let r: Routine
        if let routine { r = routine } else {
            let count = (try? context.fetchCount(FetchDescriptor<Routine>())) ?? 0
            r = Routine(name: name, order: count)
            context.insert(r)
        }
        r.name = name.hasSuffix(" Day") ? String(name.dropLast(4)) : name
        for old in r.items { context.delete(old) }
        for (i, d) in items.enumerated() {
            let ri = RoutineItem(order: i, exercise: d.exercise, sets: d.sets, repLow: d.repLow, repHigh: max(d.repLow, d.repHigh), restSeconds: d.rest, increment: d.increment)
            ri.supersetGroup = d.superset; ri.targetSeconds = d.seconds; ri.targetDistance = d.distance
            ri.routine = r
            context.insert(ri)
        }
        try? context.save()
        WidgetSync.shared.refresh()
        dismiss()
    }
}
