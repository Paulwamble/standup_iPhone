//
//  ContentView.swift
//  standup_iPhone
//
//  Stand-up reminders: every 40 minutes between 9:00 AM and 4:00 PM.
//  Alerts fire at 9:40, 10:20, 11:00, 11:40, 12:20, 1:00, 1:40, 2:20, 3:00, 3:40.
//

import SwiftUI
import UserNotifications

enum Scheduler {
    static let startMinutes = 9 * 60    // 9:00 AM
    static let endMinutes = 16 * 60     // 4:00 PM
    static let interval = 40

    // Default notification alert: on silent mode it is just a vibration.
    // (iOS doesn't let apps set a custom vibration pattern on a notification.)
    static let sound = UNNotificationSound.default

    static func schedule(weekdaysOnly: Bool) async -> Bool {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else {
            return false
        }
        center.removeAllPendingNotificationRequests()

        let weekdays: [Int?] = weekdaysOnly ? [2, 3, 4, 5, 6] : [nil]   // 2 = Monday ... 6 = Friday
        var t = startMinutes + interval
        while t < endMinutes {
            for wd in weekdays {
                var comps = DateComponents()
                comps.hour = t / 60
                comps.minute = t % 60
                comps.weekday = wd

                let content = UNMutableNotificationContent()
                content.title = "Time to stand up"
                content.body = "Stand and move for 2 minutes."
                content.sound = sound
                content.interruptionLevel = .timeSensitive

                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
                let request = UNNotificationRequest(identifier: "standup-\(t)-\(wd ?? 0)",
                                                    content: content,
                                                    trigger: trigger)
                try? await center.add(request)
            }
            t += interval
        }
        return true
    }

    static func cancel() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}

struct ContentView: View {
    @AppStorage("enabled") private var enabled = false
    @AppStorage("weekdaysOnly") private var weekdaysOnly = true
    @State private var denied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Stand-up reminders", isOn: $enabled)
                    Toggle("Weekdays only", isOn: $weekdaysOnly)
                    Button("Test buzz (dit-DAAH-dit)") { Buzz.ditDaahDit() }
                } footer: {
                    Text("Every 40 minutes from 9:00 AM to 4:00 PM. Last alert at 3:40 PM. Keep the app open to feel dit-DAAH-dit; when it's closed, iPhone uses its standard buzz.")
                }
                if denied {
                    Text("Notifications are turned off. Enable them in Settings > Stand Up.")
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Stand Up")
            .onChange(of: enabled) { _, _ in apply() }
            .onChange(of: weekdaysOnly) { _, _ in apply() }
            .onAppear { apply() }
        }
    }

    private func apply() {
        Task {
            if enabled {
                denied = !(await Scheduler.schedule(weekdaysOnly: weekdaysOnly))
                if denied { enabled = false }
            } else {
                Scheduler.cancel()
            }
        }
    }
}

#Preview {
    ContentView()
}
