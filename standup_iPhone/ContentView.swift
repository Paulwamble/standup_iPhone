//
//  ContentView.swift
//  standup_iPhone
//
//  Stand-up reminders with a choosable start time, end time,
//  reminder period and activity length, plus a check of whether you stood up.
//

import SwiftUI
import UserNotifications

struct ReminderSettings {
    var startMinutes: Int      // minutes after midnight
    var endMinutes: Int
    var interval: Int          // minutes between reminders
    var activityMinutes: Int   // how long to move
    var weekdaysOnly: Bool

    /// Reminder times (minutes after midnight): first one a full period after start, last one at or before end.
    var times: [Int] {
        guard interval > 0, endMinutes > startMinutes else { return [] }
        return Array(stride(from: startMinutes + interval, through: endMinutes, by: interval))
    }
}

enum Scheduler {
    /// iOS keeps at most 64 pending notifications per app.
    static let maxPending = 64

    // Default notification alert: on silent mode it is just a vibration.
    // (iOS doesn't let apps set a custom vibration pattern on a notification.)
    static let sound = UNNotificationSound.default

    /// True when every reminder fits as a repeating notification.
    static func usesRepeating(_ s: ReminderSettings) -> Bool {
        s.times.count * (s.weekdaysOnly ? 5 : 1) <= maxPending
    }

    static func schedule(_ s: ReminderSettings) async -> Bool {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else {
            return false
        }
        center.removeAllPendingNotificationRequests()

        let times = s.times
        guard !times.isEmpty else { return true }

        if usesRepeating(s) {
            let weekdays: [Int?] = s.weekdaysOnly ? [2, 3, 4, 5, 6] : [nil]   // 2 = Monday ... 6 = Friday
            for t in times {
                for wd in weekdays {
                    var comps = DateComponents()
                    comps.hour = t / 60
                    comps.minute = t % 60
                    comps.weekday = wd
                    await add(center, id: "standup-\(t)-\(wd ?? 0)", comps: comps, repeats: true, s)
                }
            }
        } else {
            // Too many to repeat: schedule the next 64 one at a time.
            // They are topped up every time the app is opened.
            let cal = Calendar.current
            let now = Date()
            var day = cal.startOfDay(for: now)
            var count = 0
            while count < maxPending {
                let wd = cal.component(.weekday, from: day)
                if !s.weekdaysOnly || (2...6).contains(wd) {
                    for t in times where count < maxPending {
                        guard let date = cal.date(bySettingHour: t / 60, minute: t % 60, second: 0, of: day),
                              date > now else { continue }
                        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                        await add(center, id: "standup-\(Int(date.timeIntervalSince1970))", comps: comps, repeats: false, s)
                        count += 1
                    }
                }
                guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        return true
    }

    private static func add(_ center: UNUserNotificationCenter, id: String, comps: DateComponents,
                            repeats: Bool, _ s: ReminderSettings) async {
        let content = UNMutableNotificationContent()
        content.title = "Time to stand up"
        content.body = "Stand and move for \(s.activityMinutes) minute\(s.activityMinutes == 1 ? "" : "s")."
        content.sound = sound
        content.interruptionLevel = .timeSensitive

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: repeats)
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    static func cancel() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}

struct ContentView: View {
    @AppStorage("enabled") private var enabled = false
    @AppStorage("weekdaysOnly") private var weekdaysOnly = true
    @AppStorage("startMinutes") private var startMinutes = 9 * 60
    @AppStorage("endMinutes") private var endMinutes = 16 * 60
    @AppStorage("interval") private var interval = 40
    @AppStorage("activityMinutes") private var activityMinutes = 2
    @AppStorage("sensing") private var sensing = false
    @State private var denied = false
    @State private var pending: Task<Void, Never>?
    @StateObject private var tracker = StandTracker()
    @Environment(\.scenePhase) private var scenePhase

    private var settings: ReminderSettings {
        ReminderSettings(startMinutes: startMinutes, endMinutes: endMinutes, interval: interval,
                         activityMinutes: activityMinutes, weekdaysOnly: weekdaysOnly)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Stand-up reminders", isOn: $enabled)
                }

                todaySection

                Section {
                    DatePicker("Start", selection: timeBinding($startMinutes), displayedComponents: .hourAndMinute)
                    DatePicker("End", selection: timeBinding($endMinutes), displayedComponents: .hourAndMinute)
                    Stepper("Every \(interval) minutes", value: $interval, in: 5...240, step: 5)
                    Toggle("Weekdays only", isOn: $weekdaysOnly)
                } header: {
                    Text("Schedule")
                } footer: {
                    Text(summary)
                }

                Section {
                    Stepper("Move for \(activityMinutes) minute\(activityMinutes == 1 ? "" : "s")",
                            value: $activityMinutes, in: 1...30)
                    Button("Test buzz (dit-DAAH-dit)") { Buzz.ditDaahDit() }
                } header: {
                    Text("Activity")
                } footer: {
                    Text("Keep the app open to feel dit-DAAH-dit; when it's closed, iPhone uses its standard buzz.")
                }

                if denied {
                    Text("Notifications are turned off. Enable them in Settings > Stand Up.")
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Stand Up")
            .refreshable { await refreshStands() }
            .task {
                // While the app is open, look every 30 seconds so "Excellent Stand!" comes quickly.
                while !Task.isCancelled {
                    await refreshStands()
                    await StandCelebrator.check()
                    try? await Task.sleep(for: .seconds(30))
                }
            }
            .onChange(of: enabled) { _, _ in apply() }
            .onChange(of: weekdaysOnly) { _, _ in apply() }
            .onChange(of: startMinutes) { _, _ in apply() }
            .onChange(of: endMinutes) { _, _ in apply() }
            .onChange(of: interval) { _, _ in apply() }
            .onChange(of: activityMinutes) { _, _ in apply() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    apply()
                    Task { await refreshStands() }
                }
            }
        }
    }

    // MARK: - Did I stand?

    @ViewBuilder
    private var todaySection: some View {
        Section {
            if !tracker.available {
                Text("Health data isn't available on this device.")
                    .foregroundStyle(.secondary)
            } else if !sensing {
                Button("Turn on stand sensing") {
                    Task {
                        await tracker.requestAccess()
                        sensing = true
                        StandCelebrator.start()
                        await refreshStands()
                    }
                }
            } else if tracker.checks.isEmpty {
                Text("No reminders yet today.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(tracker.checks) { check in
                    StandRow(check: check)
                }
            }
        } header: {
            Text(todayHeader)
        } footer: {
            Text(sensing
                 ? "Counts as standing if you took \(StandTracker.stepsNeeded)+ steps, or Apple Watch logged stand time, during the activity. Pull down to refresh. If every reminder shows as missed, check Settings > Health > Data Access & Devices > Stand Up."
                 : "Checks whether you got up after each reminder, using steps from your iPhone and stand time from Apple Watch in the Health app.")
        }
    }

    private var todayHeader: String {
        let decided = tracker.checks.filter { $0.result != .checking }
        guard sensing, !decided.isEmpty else { return "Today" }
        let stood = decided.filter { $0.result == .stood }.count
        return "Today: stood \(stood) of \(decided.count)"
    }

    private func refreshStands() async {
        guard sensing else { return }
        await tracker.refresh(settings)
    }

    // MARK: - Helpers

    private var summary: String {
        guard endMinutes > startMinutes else { return "End time must be after start time." }
        let t = settings.times
        guard let first = t.first, let last = t.last else {
            return "No reminders fit between the start and end time. Shorten the period or widen the hours."
        }
        var text = "\(t.count) reminder\(t.count == 1 ? "" : "s") a day, from \(clock(first)) to \(clock(last))."
        if !Scheduler.usesRepeating(settings) {
            let days = max(1, Scheduler.maxPending / t.count)
            let unit = weekdaysOnly ? "weekday" : "day"
            text += " That's more than iPhone can repeat on its own, so open the app at least every \(days) \(unit)\(days == 1 ? "" : "s") to keep them coming."
        }
        return text
    }

    private func clock(_ minutes: Int) -> String {
        let date = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    /// Lets a time picker edit a "minutes after midnight" value.
    private func timeBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: minutes.wrappedValue / 60,
                                      minute: minutes.wrappedValue % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            })
    }

    /// Reschedules after settings settle (waits briefly so stepper taps don't pile up).
    private func apply() {
        pending?.cancel()
        let s = settings
        let on = enabled
        pending = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            if on {
                denied = !(await Scheduler.schedule(s))
                if denied { enabled = false }
            } else {
                Scheduler.cancel()
            }
            await refreshStands()
        }
    }
}

#Preview {
    ContentView()
}
