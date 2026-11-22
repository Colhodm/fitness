import Foundation
import SwiftData
import SwiftUI
import UserNotifications
import WidgetKit

/// Drives the in-progress workout: creating pre-filled entries, logging sets, rest, PRs and finishing.
@MainActor
final class WorkoutSession: ObservableObject {
    static let shared = WorkoutSession()

    @Published private(set) var workout: Workout?
    @Published var isPresented = false
    @Published var expanded: PersistentIdentifier?
    @Published var summary: Workout?
    @Published var revision = 0

    let rest = RestTimer.shared
    private(set) var context: ModelContext?
    private var priorCache: [PersistentIdentifier: [Session]] = [:]
    /// The workout's exercise list as it stood at Finish (before unlogged sets/entries are dropped), used by "Update routine".
    private var finishedPlan: [(exercise: Exercise, sets: Int, supersetGroup: Int, targetSeconds: Int, targetDistance: Double)] = []

    init() {
        rest.onChange = { [weak self] in self?.pushLiveActivity() }
    }

    func attach(_ context: ModelContext) {
        guard self.context == nil else { return }
        self.context = context
        let d = FetchDescriptor<Workout>(predicate: #Predicate { $0.endedAt == nil })
        if let open = try? context.fetch(d).first {
            workout = open
            expanded = firstOpenEntry()?.persistentModelID
            rest.syncFromShared()
            startLiveActivity()
        }
    }

    var isActive: Bool { workout != nil }

    // MARK: Starting

    func start(routine: Routine?) {
        guard let context, workout == nil else { isPresented = workout != nil; return }
        let w = Workout(name: routine.map { "\($0.name)\($0.name.lowercased().hasSuffix("day") ? "" : " Day")" } ?? "Workout", routine: routine)
        context.insert(w)
        if let routine {
            for (i, item) in routine.sortedItems.enumerated() {
                guard let ex = item.exercise else { continue }
                let e = makeEntry(ex, order: i, in: w, config: ProgressionConfig(item), rest: item.restSeconds)
                e.supersetGroup = item.supersetGroup
            }
        }
        save()
        workout = w
        expanded = firstOpenEntry()?.persistentModelID
        isPresented = true
        requestNotifications()
        startLiveActivity()
    }

    func repeatLast(_ last: Workout) {
        if let r = last.routine { start(routine: r); return }
        start(routine: nil)
        for e in last.sortedEntries { if let ex = e.exercise { addExercise(ex) } }
        workout?.name = last.name
    }

    func defaultConfig(for ex: Exercise) -> (ProgressionConfig, Int) {
        if let lastEntry = Analytics.sessions(ex).last?.entry {
            return (ProgressionConfig(lastEntry), lastEntry.restSeconds)
        }
        let s = AppSettings.shared
        let item = RoutineItem(order: 0, exercise: ex)
        item.increment = ex.isUpperBody ? s.upperIncrement : s.lowerIncrement
        switch ex.kind {
        case .weightReps: item.repLow = 8; item.repHigh = 12
        case .bodyweight, .assisted: item.repLow = 8; item.repHigh = 12
        case .timed: item.repLow = 1; item.repHigh = 1; item.targetSeconds = 60; item.increment = 10
        case .distanceWeight: item.repLow = 1; item.repHigh = 1; item.targetDistance = 40 * Units.metersPerYard; item.increment = 5
        }
        let c = ProgressionConfig(item)
        item.exercise = nil
        return (c, s.defaultRest)
    }

    func addExercise(_ ex: Exercise) {
        guard let w = workout else { return }
        let (config, restSeconds) = defaultConfig(for: ex)
        let e = makeEntry(ex, order: (w.entries.map(\.order).max() ?? -1) + 1, in: w, config: config, rest: restSeconds)
        save()
        expanded = e.persistentModelID
        bump()
    }

    @discardableResult
    private func makeEntry(_ ex: Exercise, order: Int, in w: Workout, config: ProgressionConfig, rest restSeconds: Int) -> WorkoutEntry {
        let e = WorkoutEntry(order: order, exercise: ex)
        e.targetSets = config.sets
        e.repLow = config.repLow
        e.repHigh = config.repHigh
        e.increment = config.increment
        e.restSeconds = restSeconds
        let prior = Analytics.sessions(ex, excluding: w)
        let last = prior.last
        let plan = Analytics.plan(kind: ex.kind, config: config, last: last)
        e.targetSeconds = ex.kind == .timed ? (plan.seconds > 0 ? plan.seconds : config.targetSeconds) : config.targetSeconds
        e.targetDistance = ex.kind == .distanceWeight ? (plan.distance > 0 ? plan.distance : config.targetDistance) : config.targetDistance
        e.workout = w
        context?.insert(e)
        var idx = 0
        if let last {
            for wu in last.entry.sortedSets where wu.isWarmup && wu.done {
                let s = SetRecord(order: idx, isWarmup: true, weight: wu.weight, reps: wu.reps, seconds: wu.seconds, distance: wu.distance)
                s.entry = e
                context?.insert(s)
                idx += 1
            }
        }
        for i in 0..<max(1, config.sets) {
            let s = SetRecord(order: idx, weight: plan.weight, reps: i < plan.reps.count ? plan.reps[i] : config.repLow,
                              seconds: e.targetSeconds, distance: e.targetDistance)
            s.entry = e
            context?.insert(s)
            idx += 1
        }
        return e
    }

    // MARK: Sets

    func priorSessions(_ entry: WorkoutEntry) -> [Session] {
        guard let ex = entry.exercise else { return [] }
        if let c = priorCache[ex.persistentModelID] { return c }
        let s = Analytics.sessions(ex, excluding: workout)
        priorCache[ex.persistentModelID] = s
        return s
    }

    func previousSet(_ set: SetRecord, in entry: WorkoutEntry) -> SetRecord? {
        guard let last = priorSessions(entry).last else { return nil }
        let pool = last.entry.sortedSets.filter { $0.done && $0.isWarmup == set.isWarmup }
        let mine = entry.sortedSets.filter { $0.isWarmup == set.isWarmup }
        guard let i = mine.firstIndex(where: { $0 === set }), i < pool.count else { return nil }
        return pool[i]
    }

    func plan(_ entry: WorkoutEntry) -> Plan {
        guard let ex = entry.exercise else { return Plan() }
        return Analytics.plan(kind: ex.kind, config: ProgressionConfig(entry), last: priorSessions(entry).last)
    }

    func pr(_ entry: WorkoutEntry) -> PRResult? { Analytics.bestPR(entry, prior: priorSessions(entry)) }

    func toggle(_ set: SetRecord) {
        if set.done { unlog(set) } else { log(set) }
    }

    func log(_ set: SetRecord) {
        guard let entry = set.entry else { return }
        set.done = true
        set.completedAt = Date()
        let sets = entry.sortedSets
        if let i = sets.firstIndex(where: { $0 === set }) {
            for later in sets[(i + 1)...] where !later.done && !later.edited && later.isWarmup == set.isWarmup {
                later.weight = set.weight
                later.reps = set.reps
                later.seconds = set.seconds
                later.distance = set.distance
            }
        }
        save()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        advance(after: entry, loggedWarmup: set.isWarmup)
        bump()
    }

    func unlog(_ set: SetRecord) {
        set.done = false
        set.completedAt = nil
        save()
        bump()
    }

    private func advance(after entry: WorkoutEntry, loggedWarmup: Bool) {
        guard let w = workout else { return }
        let entries = w.sortedEntries
        var restSeconds = entry.restSeconds
        var nextEntry: WorkoutEntry?
        if entry.supersetGroup != 0 {
            let group = entries.filter { $0.supersetGroup == entry.supersetGroup }
            if let gi = group.firstIndex(where: { $0 === entry }) {
                let rotated = Array(group[(gi + 1)...]) + Array(group[...gi])
                nextEntry = rotated.first { $0.sortedSets.contains { !$0.done } }
                let isLastInRound = gi == group.count - 1 || !group[(gi + 1)...].contains { $0.sortedSets.contains { !$0.done } }
                if !isLastInRound { restSeconds = 0 }
                restSeconds = isLastInRound ? group.map(\.restSeconds).max() ?? restSeconds : 0
            }
        }
        if nextEntry == nil {
            if entry.sortedSets.contains(where: { !$0.done }) { nextEntry = entry }
            else { nextEntry = entries.first { $0.order > entry.order && $0.sortedSets.contains { !$0.done } } ?? firstOpenEntry() }
        }
        if let nextEntry { expanded = nextEntry.persistentModelID }
        let anythingLeft = entries.contains { $0.sortedSets.contains { !$0.done } }
        if AppSettings.shared.autoStartRest, anythingLeft, restSeconds > 0 {
            rest.start(seconds: loggedWarmup ? min(60, restSeconds) : restSeconds)
        } else {
            pushLiveActivity()
        }
    }

    func addSet(to entry: WorkoutEntry, warmup: Bool = false) {
        let sets = entry.sortedSets
        let template = warmup ? sets.first : (sets.last { !$0.isWarmup } ?? sets.last)
        let s = SetRecord(order: (sets.map(\.order).max() ?? -1) + 1, isWarmup: warmup,
                          weight: warmup ? (template?.weight ?? 0) * 0.5 : template?.weight ?? 0, reps: template?.reps ?? entry.repLow,
                          seconds: template?.seconds ?? entry.targetSeconds, distance: template?.distance ?? entry.targetDistance)
        if warmup {
            for x in sets { x.order += 1 }
            s.order = 0
            s.weight = (s.weight / 5).rounded() * 5
        }
        s.entry = entry
        context?.insert(s)
        save()
        bump()
    }

    func delete(_ set: SetRecord) {
        context?.delete(set)
        save()
        bump()
    }

    func remove(_ entry: WorkoutEntry) {
        context?.delete(entry)
        save()
        bump()
    }

    func move(_ entry: WorkoutEntry, by delta: Int) {
        guard let w = workout else { return }
        var entries = w.sortedEntries
        guard let i = entries.firstIndex(where: { $0 === entry }) else { return }
        let j = min(max(0, i + delta), entries.count - 1)
        entries.remove(at: i)
        entries.insert(entry, at: j)
        for (k, e) in entries.enumerated() { e.order = k }
        save()
        bump()
    }

    func firstOpenEntry() -> WorkoutEntry? {
        workout?.sortedEntries.first { $0.sortedSets.contains { !$0.done } } ?? workout?.sortedEntries.first
    }

    var setsDone: Int { workout?.completedSets.count ?? 0 }

    var currentIndex: Int {
        guard let w = workout, let expanded else { return 1 }
        return (w.sortedEntries.firstIndex { $0.persistentModelID == expanded } ?? 0) + 1
    }

    // MARK: Finish

    func finish() async {
        guard let w = workout, let context else { return }
        rest.skip()
        w.endedAt = Date()
        finishedPlan = w.sortedEntries.compactMap { e in
            e.exercise.map { ($0, max(1, e.workingSets.count), e.supersetGroup, e.targetSeconds, e.targetDistance) }
        }
        for e in w.entries {
            for s in e.sets where !s.done { context.delete(s) }
        }
        for e in w.entries where !e.sets.contains(where: \.done) { context.delete(e) }
        save()
        if w.entries.isEmpty {
            context.delete(w)
            save()
            reset()
            return
        }
        let saved = await HealthStore.shared.saveStrengthWorkout(name: w.name, start: w.startedAt, end: w.endedAt!)
        w.savedToHealth = saved
        save()
        LiveActivityController.shared.endAll()
        summary = w
        reset(keepPresented: true)
        WidgetSync.shared.refresh()
    }

    func discard() {
        guard let w = workout, let context else { return }
        rest.skip()
        context.delete(w)
        save()
        LiveActivityController.shared.endAll()
        reset()
    }

    private func reset(keepPresented: Bool = false) {
        workout = nil
        expanded = nil
        priorCache = [:]
        if !keepPresented { isPresented = false }
        bump()
    }

    /// Makes the routine match what was done today (exercise order and set counts).
    func updateRoutine(from w: Workout) {
        guard let routine = w.routine, let context else { return }
        let plan = finishedPlan.isEmpty
            ? w.sortedEntries.compactMap { e in e.exercise.map { ($0, max(1, e.workingSets.count), e.supersetGroup, e.targetSeconds, e.targetDistance) } }
            : finishedPlan
        let existing = routine.items
        for item in existing where !plan.contains(where: { $0.exercise === item.exercise }) {
            context.delete(item)
        }
        for (i, p) in plan.enumerated() {
            let e = w.entries.first { $0.exercise === p.exercise }
            let item = existing.first { $0.exercise === p.exercise } ?? {
                let ri = RoutineItem(order: i, exercise: p.exercise, sets: p.sets, repLow: e?.repLow ?? 8, repHigh: e?.repHigh ?? 12,
                                     restSeconds: e?.restSeconds ?? AppSettings.shared.defaultRest, increment: e?.increment ?? AppSettings.shared.upperIncrement)
                ri.routine = routine
                context.insert(ri)
                return ri
            }()
            item.order = i
            item.sets = p.sets
            item.targetSeconds = p.targetSeconds
            item.targetDistance = p.targetDistance
            item.supersetGroup = p.supersetGroup
        }
        save()
    }

    func saveAsRoutine(_ w: Workout, name: String) {
        guard let context else { return }
        let count = (try? context.fetchCount(FetchDescriptor<Routine>())) ?? 0
        let r = Routine(name: name, order: count)
        context.insert(r)
        for (i, e) in w.sortedEntries.enumerated() {
            guard let ex = e.exercise else { continue }
            let ri = RoutineItem(order: i, exercise: ex, sets: max(1, e.workingSets.count), repLow: e.repLow, repHigh: e.repHigh, restSeconds: e.restSeconds, increment: e.increment)
            ri.targetSeconds = e.targetSeconds
            ri.targetDistance = e.targetDistance
            ri.supersetGroup = e.supersetGroup
            ri.routine = r
            context.insert(ri)
        }
        w.routine = r
        save()
    }

    // MARK: Live Activity

    func liveState() -> RestActivityAttributes.ContentState {
        var name = workout?.name ?? ""
        var upNext = ""
        var target = ""
        if let w = workout,
           let entry = w.sortedEntries.first(where: { $0.persistentModelID == expanded && $0.sortedSets.contains { !$0.done } })
            ?? w.sortedEntries.first(where: { $0.sortedSets.contains { !$0.done } }),
           let ex = entry.exercise {
            name = ex.name
            let working = entry.workingSets
            if let next = entry.sortedSets.first(where: { !$0.done }) {
                if next.isWarmup { upNext = "warm-up" }
                else if let i = working.firstIndex(where: { $0 === next }) { upNext = "set \(i + 1) of \(working.count)" }
                target = Analytics.setText(next, ex.kind)
            }
        }
        return .init(restEndsAt: rest.isRunning ? rest.endsAt : nil, restStartedAt: rest.isRunning ? rest.startedAt : nil,
                     exerciseName: name, upNext: upNext, target: target, workoutStartedAt: workout?.startedAt)
    }

    func startLiveActivity() {
        guard let w = workout else { return }
        LiveActivityController.shared.start(workoutName: w.name, startedAt: w.startedAt, state: liveState())
    }

    func pushLiveActivity() {
        guard workout != nil else { return }
        LiveActivityController.shared.update(liveState())
        bump()
    }

    // MARK: Helpers

    private func requestNotifications() {
        #if DEBUG
        if SampleHealth.isEnabled { return }
        #endif
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func save() {
        try? context?.save()
    }

    private func bump() { revision &+= 1 }
}
