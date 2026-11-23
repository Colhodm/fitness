import SwiftData
import SwiftUI

@main
struct LiftRunBodyApp: App {
    let container: ModelContainer

    init() {
        let schema = Schema(AppSchema.models)
        #if DEBUG
        let inMemory = ProcessInfo.processInfo.arguments.contains("-sampleData")
        #else
        let inMemory = false
        #endif
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not open the workout store: \(error)")
        }
        let context = container.mainContext
        #if DEBUG
        if inMemory { AppGroup.defaults.removeObject(forKey: "catalogSeeded") }
        #endif
        Library.ensureCatalog(context)
        #if DEBUG
        if SampleHealth.isEnabled {
            HealthStore.shared.sample = SampleHealth.make()
            if ProcessInfo.processInfo.arguments.contains("-sampleData") && !SampleHealth.flag("-firstDay") {
                SampleLifting.seed(context)
            }
            AppSettings.shared.onboardingDone = !SampleHealth.flag("-onboarding")
            AppSettings.shared.goalWeight = 178
        }
        #endif
        WidgetSync.shared.context = context
        WorkoutSession.shared.attach(context)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .environmentObject(AppSettings.shared)
                .environmentObject(HealthStore.shared)
                .environmentObject(WorkoutSession.shared)
                .environmentObject(RestTimer.shared)
        }
        .modelContainer(container)
    }
}
