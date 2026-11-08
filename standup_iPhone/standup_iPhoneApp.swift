//
//  standup_iPhoneApp.swift
//  standup_iPhone
//

import SwiftUI
import UserNotifications

// While the app is open: show the banner and play dit-DAAH-dit.
// When the notification is tapped: play dit-DAAH-dit as well.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        await MainActor.run { Buzz.ditDaahDit() }
        return [.banner, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
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
