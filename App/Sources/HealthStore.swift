import CoreLocation
import Foundation
import HealthKit

struct BodySample: Identifiable, Hashable {
    var id = UUID()
    var date: Date
    /// Pounds for mass; fraction (0.178) for body fat.
    var value: Double
    var source: String
    var isManual = false
}

struct RunSummary: Identifiable, Hashable {
    var id: UUID
    var start: Date
    var end: Date
    var duration: TimeInterval
    var meters: Double
    var avgHR: Double?
    var source: String
    var secondsPerUnit: Double { meters > 0 ? duration / Units.runDisplay(meters) : 0 }
}

struct DaySteps: Identifiable, Hashable {
    var date: Date
    var count: Double
    var id: Date { date }
}

struct RoutePoint: Hashable {
    var latitude: Double
    var longitude: Double
    var time: Date
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

struct RunSplit: Identifiable, Hashable {
    var id: Int { index }
    var index: Int
    /// Seconds for this split, normalised to a full mile/km when the last split is partial.
    var seconds: Double
    var fraction: Double
    var hr: Double?
}

struct RunDetail {
    var route: [RoutePoint] = []
    var splits: [RunSplit] = []
    var avgHR: Double?
}

enum HealthAccess: Equatable { case unavailable, notRequested, requested }

@MainActor
final class HealthStore: ObservableObject {
    static let shared = HealthStore()

    let store = HKHealthStore()
    @Published private(set) var weights: [BodySample] = []
    @Published private(set) var bodyFat: [BodySample] = []
    @Published private(set) var lean: [BodySample] = []
    @Published private(set) var runs: [RunSummary] = []
    @Published private(set) var walks: [RunSummary] = []
    /// Daily totals, oldest first.
    @Published private(set) var steps: [DaySteps] = []
    @Published private(set) var access: HealthAccess = .notRequested
    @Published private(set) var isLoading = false
    @Published private(set) var lastRefresh: Date?
    /// Most recent sample that came from Apple Health (not typed in here).
    var latestHealthWeight: BodySample? { weights.filter { !$0.isManual }.max { $0.date < $1.date } }

    private var hkWorkouts: [UUID: HKWorkout] = [:]
    private var manual: [BodySample] = []
    #if DEBUG
    var sample: SampleHealth?
    #endif

    private let readTypes: Set<HKObjectType> = [
        HKQuantityType(.bodyMass), HKQuantityType(.bodyFatPercentage), HKQuantityType(.leanBodyMass),
        HKObjectType.workoutType(), HKSeriesType.workoutRoute(),
        HKQuantityType(.distanceWalkingRunning), HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.stepCount),
    ]
    private let shareTypes: Set<HKSampleType> = [HKObjectType.workoutType(), HKQuantityType(.bodyMass),
                                                 HKQuantityType(.distanceWalkingRunning), HKQuantityType(.activeEnergyBurned)]

    init() {
        if !HKHealthStore.isHealthDataAvailable() { access = .unavailable }
        else if AppGroup.defaults.bool(forKey: "healthRequested") { access = .requested }
    }

    var isConnected: Bool {
        #if DEBUG
        if sample != nil { return true }
        #endif
        return access == .requested
    }

    /// Returns false when the request itself failed (e.g. missing HealthKit entitlement), so callers can show an error.
    @discardableResult
    func requestAccess() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { access = .unavailable; return false }
        var ok = true
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
            AppGroup.defaults.set(true, forKey: "healthRequested")
            access = .requested
        } catch {
            print("Health authorization failed: \(error)")
            ok = false
        }
        await refresh()
        return ok
    }

    func setManual(_ entries: [ManualWeighIn]) {
        manual = entries.filter { !$0.savedToHealth }.map {
            BodySample(date: $0.date, value: $0.pounds, source: "Manual entry", isManual: true)
        }
    }

    func refresh() async {
        #if DEBUG
        if let sample {
            weights = (sample.weights + manual).sorted { $0.date < $1.date }
            bodyFat = sample.bodyFat
            lean = sample.lean
            runs = sample.runs.sorted { $0.start > $1.start }
            walks = sample.walks.sorted { $0.start > $1.start }
            steps = sample.steps
            lastRefresh = Date()
            return
        }
        #endif
        guard access == .requested else {
            weights = manual.sorted { $0.date < $1.date }
            return
        }
        isLoading = true
        defer { isLoading = false }
        // Ask again when a newer version needs types the user hasn't seen yet (steps, treadmill writes).
        if (try? await store.statusForAuthorizationRequest(toShare: shareTypes, read: readTypes)) == .shouldRequest {
            try? await store.requestAuthorization(toShare: shareTypes, read: readTypes)
        }
        let since = Calendar.current.date(byAdding: .year, value: -2, to: Date())!
        async let w = quantity(.bodyMass, unit: .pound(), since: since)
        async let f = quantity(.bodyFatPercentage, unit: .percent(), since: since)
        async let l = quantity(.leanBodyMass, unit: .pound(), since: since)
        async let r = fetchRuns(since: since)
        async let wk = fetchRuns(since: since, activity: .walking)
        async let st = dailySteps(days: 120)
        let (ws, fs, ls, rs) = await (w, f, l, r)
        walks = await wk
        steps = await st
        weights = (ws + manual).sorted { $0.date < $1.date }
        bodyFat = fs
        lean = ls
        runs = rs
        lastRefresh = Date()
    }

    private func quantity(_ id: HKQuantityTypeIdentifier, unit: HKUnit, since: Date) async -> [BodySample] {
        let type = HKQuantityType(id)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: HKQuery.predicateForSamples(withStart: since, end: nil))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)])
        do {
            let results = try await descriptor.result(for: store)
            return results.map {
                BodySample(date: $0.startDate, value: $0.quantity.doubleValue(for: unit), source: Self.sourceName($0.sourceRevision.source.name))
            }
        } catch {
            return []
        }
    }

    static func sourceName(_ raw: String) -> String {
        raw.lowercased().contains("renpho") ? "Renpho" : raw
    }

    private func dailySteps(days: Int) async -> [DaySteps] {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: Date()))!
        let type = HKQuantityType(.stepCount)
        let query = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: HKQuery.predicateForSamples(withStart: start, end: nil)),
            options: .cumulativeSum, anchorDate: start, intervalComponents: DateComponents(day: 1))
        guard let collection = try? await query.result(for: store) else { return [] }
        var out: [DaySteps] = []
        collection.enumerateStatistics(from: start, to: Date()) { s, _ in
            out.append(DaySteps(date: s.startDate, count: s.sumQuantity()?.doubleValue(for: .count()) ?? 0))
        }
        return out
    }

    private func fetchRuns(since: Date, activity: HKWorkoutActivityType = .running) async -> [RunSummary] {
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForWorkouts(with: activity), HKQuery.predicateForSamples(withStart: since, end: nil)])
        let descriptor = HKSampleQueryDescriptor(predicates: [.workout(predicate)], sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)])
        guard let workouts = try? await descriptor.result(for: store) else { return [] }
        var map: [UUID: HKWorkout] = [:]
        let distType = HKQuantityType(.distanceWalkingRunning)
        let hrType = HKQuantityType(.heartRate)
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let result = workouts.map { w -> RunSummary in
            map[w.uuid] = w
            let meters = w.statistics(for: distType)?.sumQuantity()?.doubleValue(for: .meter())
                ?? w.totalDistance?.doubleValue(for: .meter()) ?? 0
            let hr = w.statistics(for: hrType)?.averageQuantity()?.doubleValue(for: bpm)
            return RunSummary(id: w.uuid, start: w.startDate, end: w.endDate, duration: w.duration, meters: meters, avgHR: hr,
                              source: Self.deviceName(w))
        }
        hkWorkouts.merge(map) { _, new in new }
        return result
    }

    private static func deviceName(_ w: HKWorkout) -> String {
        if let model = w.device?.model, model.lowercased().contains("watch") { return "Apple Watch" }
        let name = w.sourceRevision.source.name
        return name.lowercased().contains("watch") ? "Apple Watch" : name
    }

    // MARK: Run detail

    func detail(for run: RunSummary) async -> RunDetail {
        #if DEBUG
        if let sample { return sample.detail(for: run) }
        #endif
        guard let workout = hkWorkouts[run.id] else { return RunDetail() }
        async let routeTask = route(for: workout)
        async let hrTask = heartRates(start: workout.startDate, end: workout.endDate)
        let (points, hr) = await (routeTask, hrTask)
        var detail = RunDetail(route: points)
        if points.count > 1 {
            detail.splits = Self.splits(route: points, hr: hr)
        } else {
            let distances = await distanceSamples(for: workout)
            detail.splits = Self.splits(cumulative: distances, hr: hr)
        }
        if !hr.isEmpty { detail.avgHR = hr.map(\.1).reduce(0, +) / Double(hr.count) }
        return detail
    }

    private func route(for workout: HKWorkout) async -> [RoutePoint] {
        let routeDescriptor = HKSampleQueryDescriptor(
            predicates: [.sample(type: HKSeriesType.workoutRoute(), predicate: HKQuery.predicateForObjects(from: workout))],
            sortDescriptors: [])
        guard let routes = try? await routeDescriptor.result(for: store) as? [HKWorkoutRoute], let route = routes.first else { return [] }
        return await withCheckedContinuation { cont in
            var points: [RoutePoint] = []
            var resumed = false
            let query = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                if let locations {
                    points += locations.map { RoutePoint(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude, time: $0.timestamp) }
                }
                if (done || error != nil) && !resumed {
                    resumed = true
                    cont.resume(returning: points)
                }
            }
            store.execute(query)
        }
    }

    private func heartRates(start: Date, end: Date) async -> [(Date, Double)] {
        let d = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.heartRate), predicate: HKQuery.predicateForSamples(withStart: start, end: end))],
            sortDescriptors: [SortDescriptor(\.startDate)])
        let bpm = HKUnit.count().unitDivided(by: .minute())
        return ((try? await d.result(for: store)) ?? []).map { ($0.startDate, $0.quantity.doubleValue(for: bpm)) }
    }

    /// Distance samples from the device that recorded the workout only, so phone + watch samples aren't summed.
    private func distanceSamples(for workout: HKWorkout) async -> [(Date, Double)] {
        let start = workout.startDate
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForSamples(withStart: start, end: workout.endDate, options: .strictStartDate),
            HKQuery.predicateForObjects(from: workout.sourceRevision.source),
        ])
        let d = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.distanceWalkingRunning), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)])
        var total = 0.0
        var out: [(Date, Double)] = [(start, 0)]
        for s in (try? await d.result(for: store)) ?? [] {
            total += s.quantity.doubleValue(for: .meter())
            out.append((s.endDate, total))
        }
        return out
    }

    static func splits(route: [RoutePoint], hr: [(Date, Double)]) -> [RunSplit] {
        var cumulative: [(Date, Double)] = [(route[0].time, 0)]
        var total = 0.0
        for i in 1..<route.count {
            let a = CLLocation(latitude: route[i - 1].latitude, longitude: route[i - 1].longitude)
            let b = CLLocation(latitude: route[i].latitude, longitude: route[i].longitude)
            total += b.distance(from: a)
            cumulative.append((route[i].time, total))
        }
        return splits(cumulative: cumulative, hr: hr)
    }

    /// Splits per mile (or km) from a cumulative-distance series.
    static func splits(cumulative: [(Date, Double)], hr: [(Date, Double)]) -> [RunSplit] {
        guard let first = cumulative.first, let last = cumulative.last, last.1 > 0 else { return [] }
        let unit = AppSettings.shared.unit == .lb ? Units.metersPerMile : 1000
        var result: [RunSplit] = []
        var splitStart = first.0
        var next = unit
        var prev = first
        for point in cumulative.dropFirst() {
            while point.1 >= next {
                let frac = (next - prev.1) / max(point.1 - prev.1, 0.001)
                let t = prev.0.addingTimeInterval(point.0.timeIntervalSince(prev.0) * frac)
                result.append(RunSplit(index: result.count + 1, seconds: t.timeIntervalSince(splitStart), fraction: 1, hr: avg(hr, splitStart, t)))
                splitStart = t
                next += unit
            }
            prev = point
        }
        let remaining = last.1 - (next - unit)
        if remaining / unit >= 0.1 {
            let secs = last.0.timeIntervalSince(splitStart)
            result.append(RunSplit(index: result.count + 1, seconds: secs / (remaining / unit), fraction: remaining / unit, hr: avg(hr, splitStart, last.0)))
        }
        return result
    }

    private static func avg(_ hr: [(Date, Double)], _ a: Date, _ b: Date) -> Double? {
        let v = hr.filter { $0.0 >= a && $0.0 <= b }.map(\.1)
        return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
    }

    // MARK: Writing

    /// Saves a finished lifting session as a Traditional Strength Training workout.
    func saveStrengthWorkout(name: String, start: Date, end: Date) async -> Bool {
        #if DEBUG
        if sample != nil { return true }
        #endif
        guard access == .requested, store.authorizationStatus(for: .workoutType()) == .sharingAuthorized else { return false }
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        config.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        do {
            try await builder.beginCollection(at: start)
            try await builder.addMetadata([HKMetadataKeyWorkoutBrandName: "Lift + Run + Body", "LiftRunBodyName": name])
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
            return true
        } catch {
            print("Saving workout failed: \(error)")
            return false
        }
    }

    /// Saves an indoor run or walk (e.g. read off a treadmill screen) with its distance and calories.
    func saveCardio(walk: Bool, start: Date, duration: TimeInterval, meters: Double, kcal: Double) async -> Bool {
        let end = start.addingTimeInterval(duration)
        #if DEBUG
        if sample != nil {
            let r = RunSummary(id: UUID(), start: start, end: end, duration: duration, meters: meters, avgHR: nil, source: "Treadmill")
            if walk { sample!.walks.append(r) } else { sample!.runs.append(r) }
            await refresh()
            return true
        }
        #endif
        guard access == .requested, store.authorizationStatus(for: .workoutType()) == .sharingAuthorized else { return false }
        let config = HKWorkoutConfiguration()
        config.activityType = walk ? .walking : .running
        config.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        do {
            try await builder.beginCollection(at: start)
            var samples: [HKSample] = []
            if meters > 0, store.authorizationStatus(for: HKQuantityType(.distanceWalkingRunning)) == .sharingAuthorized {
                samples.append(HKQuantitySample(type: HKQuantityType(.distanceWalkingRunning), quantity: HKQuantity(unit: .meter(), doubleValue: meters), start: start, end: end))
            }
            if kcal > 0, store.authorizationStatus(for: HKQuantityType(.activeEnergyBurned)) == .sharingAuthorized {
                samples.append(HKQuantitySample(type: HKQuantityType(.activeEnergyBurned), quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal), start: start, end: end))
            }
            if !samples.isEmpty { try await builder.addSamples(samples) }
            try await builder.addMetadata([HKMetadataKeyWorkoutBrandName: "Lift + Run + Body", HKMetadataKeyIndoorWorkout: true])
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
            await refresh()
            return true
        } catch {
            print("Saving cardio failed: \(error)")
            return false
        }
    }

    func saveWeight(pounds: Double, date: Date) async -> Bool {
        #if DEBUG
        if sample != nil { return false }
        #endif
        guard access == .requested, store.authorizationStatus(for: HKQuantityType(.bodyMass)) == .sharingAuthorized else { return false }
        let s = HKQuantitySample(type: HKQuantityType(.bodyMass), quantity: HKQuantity(unit: .pound(), doubleValue: pounds), start: date, end: date)
        do {
            try await store.save(s)
            return true
        } catch {
            return false
        }
    }

    var canWriteWorkouts: Bool {
        #if DEBUG
        if sample != nil { return true }
        #endif
        return access == .requested && store.authorizationStatus(for: .workoutType()) == .sharingAuthorized
    }
}
