import Foundation
import SwiftData
import UserNotifications

/// Manages the app icon badge count based on missed (passed but uncompleted) prayers.
@MainActor
enum BadgeService {

    /// Counts prayers that have passed today but are not marked complete, and updates the badge.
    static func updateBadge(cloudContext: ModelContext, todayTimes: DailyPrayerTimes?) {
        let count = missedPrayerCount(cloudContext: cloudContext, todayTimes: todayTimes)
        Task {
            try? await UNUserNotificationCenter.current().setBadgeCount(count)
        }
    }

    /// Returns the number of prayers that have passed today but are not completed.
    static func missedPrayerCount(cloudContext: ModelContext, todayTimes: DailyPrayerTimes?) -> Int {
        guard let times = todayTimes else { return 0 }

        let startOfDay = Calendar.current.startOfDay(for: Date())
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        let descriptor = FetchDescriptor<PrayerCompletion>(
            predicate: #Predicate { $0.date >= startOfDay && $0.date < endOfDay }
        )
        let completions = (try? cloudContext.fetch(descriptor)) ?? []

        var missed = 0
        for prayer in Prayer.allCases {
            guard let time = times.time(for: prayer), time < Date() else { continue }
            let isCompleted = completions.first(where: { $0.prayerName == prayer.rawValue })?.isCompleted ?? false
            if !isCompleted {
                missed += 1
            }
        }
        return missed
    }
}
