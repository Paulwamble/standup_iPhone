//
//  StandTracker.swift
//  standup_iPhone
//
//  Checks whether you actually got up after each reminder, using data in the Health app:
//  steps (from iPhone or Apple Watch) and stand time (from Apple Watch).
//

import SwiftUI
import Combine
import HealthKit

struct StandCheck: Identifiable {
    enum Result { case stood, missed, checking }

    let time: Date
    let steps: Int
    let standMinutes: Int
    let result: Result

    var id: Date { time }
}

@MainActor
final class StandTracker: ObservableObject {
    @Published private(set) var checks: [StandCheck] = []
    let available = HKHealthStore.isHealthDataAvailable()

    private let store = HKHealthStore()

    /// Steps during the activity that count as having stood up.
    static let stepsNeeded = 15
    /// Extra time after the activity to still count movement.
    static let grace: TimeInterval = 3 * 60
    /// Apple Watch data can take a few minutes to reach the Health app.
    static let syncDelay: TimeInterval = 10 * 60

    private let readTypes: Set<HKObjectType> = [
        HKQuantityType(.stepCount),
        HKQuantityType(.appleStandTime),
    ]

    func requestAccess() async {
        guard available else { return }
        try? await store.requestAuthorization(toShare: [], read: readTypes)
    }

    /// Looks at each of today's reminders that has already happened.
    func refresh(_ s: ReminderSettings) async {
        guard available else { return }
        let cal = Calendar.current
        let now = Date()
        let today = cal.startOfDay(for: now)

        if s.weekdaysOnly && !(2...6).contains(cal.component(.weekday, from: today)) {
            checks = []
            return
        }

        var results: [StandCheck] = []
        for t in s.times {
            guard let start = cal.date(bySettingHour: t / 60, minute: t % 60, second: 0, of: today),
                  start <= now else { continue }
            let end = start.addingTimeInterval(Double(s.activityMinutes) * 60 + Self.grace)

            let steps = Int(await sum(.stepCount, unit: .count(), from: start, to: end))
            let stand = Int(await sum(.appleStandTime, unit: .minute(), from: start, to: end))

            let result: StandCheck.Result
            if steps >= Self.stepsNeeded || stand > 0 {
                result = .stood
            } else if now < end.addingTimeInterval(Self.syncDelay) {
                result = .checking
            } else {
                result = .missed
            }
            results.append(StandCheck(time: start, steps: steps, standMinutes: stand, result: result))
        }
        checks = results
    }

    private func sum(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date) async -> Double {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(id), predicate: predicate),
            options: .cumulativeSum)
        let stats = try? await descriptor.result(for: store)
        return stats?.sumQuantity()?.doubleValue(for: unit) ?? 0
    }
}

struct StandRow: View {
    let check: StandCheck

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(check.time.formatted(date: .omitted, time: .shortened))
            Spacer()
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var icon: String {
        switch check.result {
        case .stood: "checkmark.circle.fill"
        case .missed: "xmark.circle.fill"
        case .checking: "clock"
        }
    }

    private var color: Color {
        switch check.result {
        case .stood: .green
        case .missed: .red
        case .checking: .secondary
        }
    }

    private var detail: String {
        switch check.result {
        case .stood:
            check.standMinutes > 0 ? "\(check.standMinutes) min standing" : "\(check.steps) steps"
        case .missed:
            check.steps > 0 ? "Only \(check.steps) steps" : "No movement"
        case .checking:
            "Checking…"
        }
    }
}
