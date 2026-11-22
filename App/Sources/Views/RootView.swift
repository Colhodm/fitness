import SwiftData
import SwiftUI

enum AppTab: String, CaseIterable { case today, lift, run, body, trends }

enum Route: Hashable {
    case exercise(PersistentIdentifier)
    case newExercise
    case routine(PersistentIdentifier?)
    case run(UUID)
    case runs
    case settings
    case importNotes
}

final class Router: ObservableObject {
    static let shared = Router()
    @Published var tab: AppTab = .today
    @Published var paths: [AppTab: NavigationPath] = [:]
    func path(_ t: AppTab) -> Binding<NavigationPath> {
        Binding(get: { self.paths[t] ?? NavigationPath() }, set: { self.paths[t] = $0 })
    }
    func push(_ r: Route, on t: AppTab? = nil) {
        let t = t ?? tab
        var p = paths[t] ?? NavigationPath()
        p.append(r)
        paths[t] = p
        tab = t
    }
}

struct RootView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var health: HealthStore
    @EnvironmentObject var session: WorkoutSession
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var phase
    @StateObject private var router = Router.shared
    @Query private var manual: [ManualWeighIn]

    var body: some View {
        TabView(selection: $router.tab) {
            stack(.today) { TodayView() }
                .tabItem { Label("Today", systemImage: "house") }.tag(AppTab.today)
            stack(.lift) { LiftHomeView() }
                .tabItem { Label("Lift", systemImage: "dumbbell") }.tag(AppTab.lift)
            stack(.run) { RunsListView() }
                .tabItem { Label("Run", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }.tag(AppTab.run)
            stack(.body) { BodyView() }
                .tabItem { Label("Body", systemImage: "scalemass") }.tag(AppTab.body)
            stack(.trends) { TrendsView() }
                .tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }.tag(AppTab.trends)
        }
        .tint([.run, .body].contains(router.tab) ? Palette.cyan : Palette.orange)
        .environmentObject(router)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if session.isActive && !session.isPresented { ActiveWorkoutBar().padding(.bottom, 52) }
        }
        .fullScreenCover(isPresented: $session.isPresented) {
            ActiveWorkoutView()
                .environmentObject(settings).environmentObject(health).environmentObject(session).environmentObject(RestTimer.shared)
        }
        .fullScreenCover(isPresented: Binding(get: { !settings.onboardingDone }, set: { settings.onboardingDone = !$0 })) {
            OnboardingView().environmentObject(settings).environmentObject(health)
        }
        .task {
            health.setManual(manual)
            await health.refresh()
            WidgetSync.shared.refresh()
            #if DEBUG
            DebugLaunch.apply(router: router, context: context)
            #endif
        }
        .onChange(of: manual.count) { _, _ in
            health.setManual(manual)
            Task { await health.refresh() }
        }
        .onChange(of: phase) { _, p in
            if p == .active { RestTimer.shared.syncFromShared(); Task { await health.refresh(); WidgetSync.shared.refresh() } }
        }
        .onOpenURL { url in
            switch url.host {
            case "workout": session.isPresented = session.isActive
            case "start":
                let id = url.pathComponents.dropFirst().first
                let routines = (try? context.fetch(FetchDescriptor<Routine>())) ?? []
                session.start(routine: routines.first { $0.uuid.uuidString == id })
            case "body": router.tab = .body
            case "today": router.tab = .today
            default: break
            }
        }
    }

    private func stack<V: View>(_ t: AppTab, @ViewBuilder _ v: () -> V) -> some View {
        NavigationStack(path: router.path(t)) {
            v().navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
    }
}

struct RouteView: View {
    let route: Route
    @Environment(\.modelContext) private var context
    var body: some View {
        switch route {
        case .exercise(let id):
            if let ex = context.model(for: id) as? Exercise { ExerciseHistoryView(exercise: ex) }
        case .newExercise: ExerciseEditorView()
        case .routine(let id): RoutineEditorView(routine: id.flatMap { context.model(for: $0) as? Routine })
        case .run(let id): RunDetailView(runID: id)
        case .runs: RunsListView()
        case .settings: SettingsView()
        case .importNotes: ImportNotesView()
        }
    }
}

/// Mini bar shown above the tab bar while a workout is minimized.
struct ActiveWorkoutBar: View {
    @EnvironmentObject var session: WorkoutSession
    @EnvironmentObject var rest: RestTimer
    var body: some View {
        Button { session.isPresented = true } label: {
            HStack {
                Image(systemName: "dumbbell.fill").foregroundStyle(Palette.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.workout?.name ?? "Workout").font(.system(size: 15, weight: .semibold))
                    Text("\(session.setsDone) sets done").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                }
                Spacer()
                if rest.isRunning {
                    Text("Rest \(Fmt.clock(Int(rest.remaining.rounded(.up))))").font(.system(size: 15, weight: .semibold)).monospacedDigit().foregroundStyle(Palette.orange)
                } else if let start = session.workout?.startedAt {
                    Text(start, style: .timer).font(.system(size: 15, weight: .semibold)).monospacedDigit()
                }
            }
            .padding(.horizontal, 16).frame(height: 54)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
/// Launch arguments used to stage Simulator screenshots, e.g. `-sampleData -tab lift -open exercise:Bench\ Press`.
enum DebugLaunch {
    @MainActor static func apply(router: Router, context: ModelContext) {
        let args = ProcessInfo.processInfo.arguments
        func value(_ key: String) -> String? { args.firstIndex(of: key).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } }
        if let t = value("-tab"), let tab = AppTab(rawValue: t) { router.tab = tab }
        if let open = value("-open") {
            let parts = open.split(separator: ":", maxSplits: 1).map(String.init)
            switch parts[0] {
            case "exercise":
                if let ex = Library.exercise(named: parts[1], in: context) { router.push(.exercise(ex.persistentModelID)) }
            case "run":
                let key = parts.count > 1 ? parts[1] : "0"
                Task {
                    await HealthStore.shared.refresh()
                    let runs = HealthStore.shared.runs
                    let run = Int(key).flatMap { runs.indices.contains($0) ? runs[$0] : nil }
                        ?? (key == "long" ? runs.first { $0.meters > 12_000 } : runs.first { Fmt.runDist($0.meters, decimals: 2) == key })
                    if let run { router.push(.run(run.id)) }
                }
            case "settings": router.push(.settings)
            case "import": router.push(.importNotes)
            case "newExercise": router.push(.newExercise)
            case "routine":
                let r = (try? context.fetch(FetchDescriptor<Routine>()))?.first { $0.name == (parts.count > 1 ? parts[1] : "Pull") }
                router.push(.routine(r?.persistentModelID))
            default: break
            }
        }
        let session = WorkoutSession.shared
        if let name = value("-active") {
            let routines = (try? context.fetch(FetchDescriptor<Routine>())) ?? []
            session.start(routine: routines.first { $0.name == name })
            session.demoProgress(sets: Int(value("-activeSets") ?? "") ?? 4)
        }
        if args.contains("-summary") {
            let d = FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
            if let w = try? context.fetch(d).first(where: { $0.endedAt != nil }) { session.summary = w; session.isPresented = true }
        }
    }
}
#endif
