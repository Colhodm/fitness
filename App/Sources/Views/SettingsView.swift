import SwiftData
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var health: HealthStore
    @EnvironmentObject var router: Router
    @Environment(\.modelContext) private var context
    @State private var editingRest = false
    @State private var wrappedYear: YearItem?

    var body: some View {
        Form {
            Section("Units and equipment") {
                HStack {
                    Text("Units")
                    Spacer()
                    SegmentedPicker(options: [(WeightUnit.lb, "lb"), (WeightUnit.kg, "kg")], selection: $settings.unit).frame(width: 110)
                }
                Stepper(value: settings.unit == .lb ? $settings.barWeightLb : $settings.barWeightKg, in: 0...100, step: settings.unit == .lb ? 5 : 2.5) {
                    HStack { Text("Barbell weight"); Spacer(); Text("\(Fmt.num(settings.barWeight)) \(Units.unitLabel)").foregroundStyle(Palette.secondary) }
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Text("Plates at your gym"); Spacer(); Text("used for plate math").font(.system(size: 13)).foregroundStyle(Palette.secondary) }
                    let all = settings.unit == .lb ? AppSettings.allPlatesLb : AppSettings.allPlatesKg
                    HStack(spacing: 6) {
                        ForEach(all, id: \.self) { p in
                            let on = settings.plates.contains(p)
                            Button { togglePlate(p) } label: {
                                Text(Fmt.num(p, maxDecimals: 2)).font(.system(size: 15, weight: .semibold)).foregroundStyle(on ? .black : Palette.secondary)
                                    .frame(maxWidth: .infinity).frame(height: 34).background(on ? Palette.orange : Palette.field, in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.vertical, 4)
                NavigationLink {
                    Form {
                        Stepper("From \(Fmt.num(settings.dumbbellMin)) \(Units.unitLabel)", value: $settings.dumbbellMin, in: 1...50, step: 1)
                        Stepper("Up to \(Fmt.num(settings.dumbbellMax)) \(Units.unitLabel)", value: $settings.dumbbellMax, in: 20...200, step: 5)
                        Stepper("Every \(Fmt.num(settings.dumbbellStep)) \(Units.unitLabel)", value: $settings.dumbbellStep, in: 1...10, step: 0.5)
                    }
                    .screenBackground().navigationTitle("Dumbbells")
                } label: {
                    HStack { Text("Dumbbells"); Spacer(); Text("\(Fmt.num(settings.dumbbellMin))–\(Fmt.num(settings.dumbbellMax)) \(Units.unitLabel), every \(Fmt.num(settings.dumbbellStep))").foregroundStyle(Palette.secondary) }
                }
            }
            Section("Rest timer") {
                Stepper(value: $settings.defaultRest, in: 15...600, step: 15) {
                    HStack { Text("Default rest"); Spacer(); Text(Fmt.clock(settings.defaultRest)).foregroundStyle(Palette.secondary).monospacedDigit() }
                }
                Toggle("Start after each set", isOn: $settings.autoStartRest).tint(Palette.orange)
                Toggle("Haptic 10 s before end", isOn: $settings.hapticBeforeEnd).tint(Palette.orange)
            }
            Section("Default weight increase") {
                Stepper(value: $settings.upperIncrement, in: 1...25, step: settings.unit == .lb ? 2.5 : 1.1023) {
                    HStack { Text("Upper body"); Spacer(); Text("+\(Fmt.wu(settings.upperIncrement))").foregroundStyle(Palette.secondary) }
                }
                Stepper(value: $settings.lowerIncrement, in: 1...50, step: settings.unit == .lb ? 5 : 2.2046) {
                    HStack { Text("Lower body"); Spacer(); Text("+\(Fmt.wu(settings.lowerIncrement))").foregroundStyle(Palette.secondary) }
                }
            }
            Section("Goals") {
                Stepper("Lifting: \(settings.weeklyLiftGoal) sessions / week", value: $settings.weeklyLiftGoal, in: 1...7)
                Stepper("Running: \(Fmt.num(settings.weeklyRunGoal)) mi / week", value: $settings.weeklyRunGoal, in: 0...100, step: 1)
                Stepper(value: $settings.goalWeight, in: 0...400, step: 1) {
                    HStack { Text("Goal weight"); Spacer(); Text(settings.goalWeight > 0 ? Fmt.wu(settings.goalWeight) : "None").foregroundStyle(Palette.secondary) }
                }
                Stepper(value: $settings.goalRate, in: -2...2, step: 0.25) {
                    HStack { Text("Goal rate"); Spacer(); Text("\(Fmt.signed(Units.display(settings.goalRate), decimals: 2)) \(Units.unitLabel)/wk").foregroundStyle(Palette.secondary) }
                }
            }
            Section("Progress photos") {
                Toggle("Lock with Face ID", isOn: $settings.photoLock).tint(Palette.cyan)
                Toggle("Include in iCloud backup", isOn: $settings.photoBackup).tint(Palette.cyan)
                Picker("Reminder", selection: $settings.photoReminderWeeks) {
                    Text("Off").tag(0)
                    Text("Every week").tag(1)
                    Text("Every 2 weeks").tag(2)
                    Text("Every 4 weeks").tag(4)
                }
                if settings.photoReminderWeeks > 0 {
                    DatePicker("Reminder time", selection: reminderTime, displayedComponents: .hourAndMinute)
                }
            }
            Section {
                if Wrapped.isUnlocked(Wrapped.currentYear) {
                    Button("Your \(String(Wrapped.currentYear)) in training") { wrappedYear = YearItem(year: Wrapped.currentYear) }
                } else {
                    Button("Preview \(String(Wrapped.currentYear)) so far") { wrappedYear = YearItem(year: Wrapped.currentYear) }
                }
                Button("Your \(String(Wrapped.currentYear - 1)) in training") { wrappedYear = YearItem(year: Wrapped.currentYear - 1) }
            } header: {
                Text("Your year")
            } footer: {
                if !Wrapped.isUnlocked(Wrapped.currentYear) { Text("Your \(String(Wrapped.currentYear)) unlocks Dec 1.") }
            }
            Section("Data") {
                Button { Task { await health.requestAccess() } } label: {
                    HStack {
                        Text("Apple Health").foregroundStyle(.white)
                        Spacer()
                        Text(health.isConnected ? "Connected" : "Connect").foregroundStyle(Palette.cyan)
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.tertiary)
                    }
                }
                NavigationLink("Import from Notes") { ImportNotesView() }
                #if DEBUG
                Button("Load sample data (debug)") {
                    AppGroup.defaults.set(true, forKey: "debugSampleData")
                    health.sample = SampleHealth.make()
                    SampleLifting.seed(context)
                    Task { await health.refresh(); WidgetSync.shared.refresh() }
                }
                Button("Erase all workouts (debug)", role: .destructive) {
                    AppGroup.defaults.set(false, forKey: "debugSampleData")
                    health.sample = nil
                    SampleLifting.eraseAll(context)
                    Task { await health.refresh(); WidgetSync.shared.refresh() }
                }
                #endif
            }
        }
        .tint(Palette.orange)
        .screenBackground()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .onChange(of: settings.unit) { _, _ in WidgetSync.shared.refresh() }
        .onChange(of: settings.weeklyLiftGoal) { _, _ in WidgetSync.shared.refresh() }
        .onChange(of: settings.photoBackup) { _, _ in PhotoStore.applyBackupSetting() }
        .onChange(of: settings.photoReminderWeeks) { _, _ in PhotoStore.scheduleReminder(context: context) }
        .onChange(of: settings.photoReminderMinutes) { _, _ in PhotoStore.scheduleReminder(context: context) }
        .fullScreenCover(item: $wrappedYear) { WrappedView(year: $0.year) }
    }

    private var reminderTime: Binding<Date> {
        Binding(
            get: { Calendar.current.startOfDay(for: Date()).addingTimeInterval(Double(settings.photoReminderMinutes) * 60) },
            set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                settings.photoReminderMinutes = (c.hour ?? 8) * 60 + (c.minute ?? 0)
            })
    }

    private func togglePlate(_ p: Double) {
        if settings.unit == .lb {
            if let i = settings.platesLb.firstIndex(of: p) { settings.platesLb.remove(at: i) } else { settings.platesLb.append(p) }
        } else {
            if let i = settings.platesKg.firstIndex(of: p) { settings.platesKg.remove(at: i) } else { settings.platesKg.append(p) }
        }
    }
}

struct YearItem: Identifiable {
    let year: Int
    var id: Int { year }
}
