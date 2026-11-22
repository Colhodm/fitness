import SwiftUI

struct SetKeypad: View {
    @EnvironmentObject var session: WorkoutSession
    @EnvironmentObject var settings: AppSettings
    let target: KeypadTarget
    let onClose: () -> Void
    let onChange: (KeypadTarget) -> Void
    @State private var buffer = ""

    private var rec: SetRecord { target.set }
    private var entry: WorkoutEntry? { rec.entry }
    private var kind: ExerciseKind { entry?.exercise?.kind ?? .weightReps }
    private var fields: (SetField, SetField) { Self.fields(for: kind) }

    static func fields(for kind: ExerciseKind) -> (SetField, SetField) {
        switch kind {
        case .timed: (.weight, .time)
        case .distanceWeight: (.weight, .distance)
        default: (.weight, .reps)
        }
    }

    static func text(_ s: SetRecord, _ f: SetField, _ kind: ExerciseKind) -> String {
        switch f {
        case .weight: Fmt.w(s.weight)
        case .reps: "\(s.reps)"
        case .time: Fmt.clock(s.seconds)
        case .distance: Fmt.dist(s.distance)
        }
    }

    private func label(_ f: SetField) -> String {
        switch f {
        case .weight: kind == .assisted ? "Assist" : (kind == .bodyweight || kind == .timed ? "Added" : "Weight")
        case .reps: "Reps"
        case .time: "Time"
        case .distance: "Distance"
        }
    }

    private var unitLabel: String {
        switch target.field {
        case .weight: Units.unitLabel
        case .reps: rec.reps == 1 ? "rep" : "reps"
        case .time: ""
        case .distance: Units.distanceLabel
        }
    }

    private var steps: [Double] {
        switch target.field {
        case .weight: settings.unit == .lb ? [-5, 5, 10] : [-2.5, 2.5, 5]
        case .reps: [-1, 1, 2]
        case .time: [-10, 10, 30]
        case .distance: [-10, 10, 20]
        }
    }

    private var previous: SetRecord? { entry.flatMap { session.previousSet(rec, in: $0) } }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                SegmentedPicker(options: [(fields.0, label(fields.0)), (fields.1, label(fields.1))],
                                selection: Binding(get: { target.field }, set: { switchTo($0) }))
                    .frame(width: 170)
                Spacer()
                Button("Done", action: onClose).font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.orange)
            }
            HStack(alignment: .center) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(Self.text(rec, target.field, kind)).font(.system(size: 44, weight: .bold)).monospacedDigit()
                    Text(unitLabel).font(.system(size: 20, weight: .semibold)).foregroundStyle(Palette.secondary)
                }
                Spacer()
                if target.field == .weight { plateMath }
            }
            HStack(spacing: 8) {
                ForEach(steps, id: \.self) { s in
                    key(s > 0 ? "+\(Fmt.num(s))" : "−\(Fmt.num(-s))", height: 40) { bump(s) }
                }
                if let previous {
                    Button { apply(previousValue(previous)) } label: {
                        Text("Last: \(Self.text(previous, target.field, kind))").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.orange)
                            .frame(maxWidth: .infinity).frame(height: 40).background(Palette.orange.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "⌫"], id: \.self) { k in
                    key(k, height: 46, big: true) { press(k) }
                        .disabled(k == "." && (target.field != .weight))
                }
            }
            Button(action: next) {
                HStack {
                    Text(target.field == fields.0 ? "Next: \(label(fields.1).lowercased())" : "Log set")
                    Image(systemName: target.field == fields.0 ? "arrow.right" : "checkmark")
                }
                .font(.system(size: 17, weight: .semibold)).foregroundStyle(.black)
                .frame(maxWidth: .infinity).frame(height: 50).background(Palette.orange, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .padding(.bottom, 8)
        .background(Palette.card.ignoresSafeArea(edges: .bottom))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20))
        .onChange(of: target) { _, _ in buffer = "" }
    }

    private var plateMath: some View {
        let ex = entry?.exercise
        let bar = settings.barWeight
        let display = Units.display(rec.weight)
        return VStack(alignment: .trailing, spacing: 4) {
            if ex?.equipment == .barbell {
                Text("Per side on a \(Fmt.num(bar)) \(Units.unitLabel) bar").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                let r = PlateMath.perSide(total: display, bar: bar, plates: settings.plates)
                HStack(spacing: 6) {
                    HStack(spacing: 2) {
                        ForEach(Array(r.plates.enumerated()), id: \.offset) { _, p in
                            RoundedRectangle(cornerRadius: 2).fill(Palette.orange.opacity(0.5 + 0.5 * p / (settings.plates.first ?? p)))
                                .frame(width: 6, height: 12 + 18 * p / (settings.plates.first ?? p))
                        }
                    }
                    Text(r.plates.isEmpty ? "Empty bar" : r.plates.map { Fmt.num($0) }.joined(separator: " + "))
                        .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                    if r.remainder > 0.01 { Text("(+\(Fmt.num(r.remainder)))").font(.system(size: 12)).foregroundStyle(Palette.yellow) }
                }
            } else if ex?.equipment == .dumbbell {
                Text(ex?.perSide == true ? "Per hand" : "Dumbbell").font(.system(size: 12)).foregroundStyle(Palette.secondary)
            }
        }
    }

    private func key(_ t: String, height: CGFloat, big: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if t == "⌫" { Image(systemName: "delete.left") } else { Text(t) }
            }
            .font(.system(size: big ? 24 : 15, weight: big ? .regular : .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity).frame(height: height)
            .background(Palette.fieldHigh, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: Editing

    private func currentValue() -> Double {
        switch target.field {
        case .weight: Units.display(rec.weight)
        case .reps: Double(rec.reps)
        case .time: Double(rec.seconds)
        case .distance: Units.distanceDisplay(rec.distance)
        }
    }

    private func previousValue(_ p: SetRecord) -> Double {
        switch target.field {
        case .weight: Units.display(p.weight)
        case .reps: Double(p.reps)
        case .time: Double(p.seconds)
        case .distance: Units.distanceDisplay(p.distance)
        }
    }

    private func apply(_ v: Double) {
        let v = max(0, v)
        switch target.field {
        case .weight: rec.weight = Units.pounds(fromDisplay: v)
        case .reps: rec.reps = Int(v.rounded())
        case .time: rec.seconds = Int(v.rounded())
        case .distance: rec.distance = Units.meters(fromDisplay: v)
        }
        rec.edited = true
        session.save()
        session.pushLiveActivity()
    }

    private func bump(_ s: Double) { buffer = ""; apply(currentValue() + s) }

    private func press(_ k: String) {
        if k == "⌫" { buffer = String(buffer.dropLast()) }
        else if k == "." { if !buffer.contains(".") { buffer += buffer.isEmpty ? "0." : "." } }
        else if buffer.count < 6 { buffer += k }
        if target.field == .time {
            let digits = Int(buffer) ?? 0
            apply(Double((digits / 100) * 60 + digits % 100))
        } else {
            apply(Double(buffer) ?? 0)
        }
    }

    private func switchTo(_ f: SetField) { buffer = ""; onChange(KeypadTarget(set: rec, field: f)) }

    private func next() {
        if target.field == fields.0 { switchTo(fields.1); return }
        session.log(rec)
        let nextEntry = session.workout?.sortedEntries.first { $0.persistentModelID == session.expanded } ?? entry
        if let e = nextEntry, let open = e.sortedSets.first(where: { !$0.done }) {
            onChange(KeypadTarget(set: open, field: fields.0))
        } else {
            onClose()
        }
    }
}

enum PlateMath {
    /// Greedy plate loading for one side of the bar.
    static func perSide(total: Double, bar: Double, plates: [Double]) -> (plates: [Double], remainder: Double) {
        var side = max(0, (total - bar) / 2)
        var out: [Double] = []
        for p in plates.sorted(by: >) where p > 0 {
            while side + 1e-6 >= p { out.append(p); side -= p }
        }
        return (out, side * 2)
    }
}
