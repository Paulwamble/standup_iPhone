//
//  standup_iPhoneApp.swift
//  standup_iPhone
//

import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Lets HealthKit wake the app in the background to send "Excellent Stand!".
        StandCelebrator.start()
        return true
    }

    // While the app is open: stand-up reminders show a banner and play dit-DAAH-dit;
    // "Excellent Stand!" shows a banner with the normal sound.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let isCelebration = notification.request.identifier.hasPrefix("celebrate-")
        if isCelebration {
            return [.banner, .list, .sound]
        }
        await MainActor.run { Buzz.ditDaahDit() }
        return [.banner, .list]
    }

    // Tapping a stand-up reminder plays dit-DAAH-dit.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        guard !response.notification.request.identifier.hasPrefix("celebrate-") else { return }
        await MainActor.run { Buzz.ditDaahDit() }
    }
}

@main
struct standup_iPhoneApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
