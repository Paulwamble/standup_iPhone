//
//  StandCelebrator.swift
//  standup_iPhone
//
//  After a stand-up reminder, watches the Health app for steps or stand time and,
//  once you've actually stood up, sends an "Excellent Stand!" notification.
//

import Foundation
import HealthKit
import UserNotifications

extension ReminderSettings {
    /// The settings saved by the app's controls (same keys as the @AppStorage values in ContentView).
    static var saved: ReminderSettings {
        let d = UserDefaults.standard
        func int(_ key: String, _ fallback: Int) -> Int {
            d.object(forKey: key) == nil ? fallback : d.integer(forKey: key)
        }
        return ReminderSettings(
            startMinutes: int("startMinutes", 9 * 60),
            endMinutes: int("endMinutes", 16 * 60),
            interval: int("interval", 40),
            activityMinutes: int("activityMinutes", 2),
            weekdaysOnly: d.object(forKey: "weekdaysOnly") == nil ? true : d.bool(forKey: "weekdaysOnly"))
    }
}

@MainActor
enum StandCelebrator {
    /// Identifier prefix for the "Excellent Stand!" notification.
    static let idPrefix = "celebrate-"

    /// Don't congratulate for a stand that ended more than this long ago.
    private static let staleAfter: TimeInterval = 60 * 60
    private static let celebratedKey = "lastCelebratedReminder"

    private static let store = HKHealthStore()
    private static var observing = false

    /// Ask HealthKit to wake the app when new steps or stand time arrive.
    /// Called at launch and again right after Health access is granted.
    static func start() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let types = [HKQuantityType(.stepCount), HKQuantityType(.appleStandTime)]

        if !observing {
            observing = true
            for type in types {
                let query = HKObserverQuery(sampleType: type, predicate: nil) { @Sendable _, completion, _ in
                    Task { @MainActor in
                        await check()
                        completion()
                    }
                }
                store.execute(query)
            }
        }
        for type in types {
            Task { try? await store.enableBackgroundDelivery(for: type, frequency: .immediate) }
        }
    }

    /// Sends "Excellent Stand!" once for the latest reminder, as soon as it counts as stood.
    static func check() async {
        let d = UserDefaults.standard
        guard d.bool(forKey: "enabled"), d.bool(forKey: "sensing") else { return }

        let settings = ReminderSettings.saved
        let tracker = StandTracker()
        await tracker.refresh(settings)
        guard let latest = tracker.checks.last, latest.result == .stood else { return }

        // Only once per reminder.
        let stamp = latest.time.timeIntervalSince1970
        guard stamp > d.double(forKey: celebratedKey) else { return }

        // Skip it if the news is too old to be worth a notification.
        let windowEnd = latest.time.addingTimeInterval(Double(settings.activityMinutes) * 60 + StandTracker.grace)
        guard Date() < windowEnd.addingTimeInterval(staleAfter) else { return }

        d.set(stamp, forKey: celebratedKey)

        let content = UNMutableNotificationContent()
        content.title = "Excellent Stand!"
        content.body = latest.standMinutes > 0
            ? "You stood for \(latest.standMinutes) min after the \(latest.time.formatted(date: .omitted, time: .shortened)) reminder."
            : "\(latest.steps) steps after the \(latest.time.formatted(date: .omitted, time: .shortened)) reminder. Keep it up!"
        content.sound = .default

        let request = UNNotificationRequest(identifier: "\(idPrefix)\(Int(stamp))", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
