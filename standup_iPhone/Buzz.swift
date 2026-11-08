//
//  Buzz.swift
//  standup_iPhone
//
//  Plays the "dit-DAAH-dit" vibration with Core Haptics.
//

import CoreHaptics

enum Buzz {
    // Kept alive while the pattern plays.
    private static var engine: CHHapticEngine?

    // (start time, length) in seconds: short, long, short.
    private static let pattern: [(TimeInterval, TimeInterval)] = [
        (0.00, 0.12),   // dit
        (0.27, 0.45),   // DAAH
        (0.87, 0.12),   // dit
    ]

    static func ditDaahDit() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let engine = try CHHapticEngine()
            engine.isAutoShutdownEnabled = true
            try engine.start()

            let events = pattern.map { start, length in
                CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5),
                    ],
                    relativeTime: start,
                    duration: length)
            }
            let player = try engine.makePlayer(with: CHHapticPattern(events: events, parameters: []))
            try player.start(atTime: CHHapticTimeImmediate)
            self.engine = engine
        } catch {
            print("Haptics failed: \(error)")
        }
    }
}
