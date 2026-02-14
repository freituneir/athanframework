import Foundation
import SwiftData

/// Tracks whether a prayer was completed on a given day.
/// Resets daily — each day starts with 5 uncompleted prayers.
@Model
final class PrayerCompletion {
    var id: UUID = UUID()

    /// Normalized to start of day (midnight local time).
    var date: Date = Date()

    /// The raw value of the Prayer enum.
    var prayerName: String = ""

    var isCompleted: Bool = false
    var completedAt: Date?

    init() {}

    convenience init(date: Date, prayer: Prayer) {
        self.init()
        self.date = Calendar.current.startOfDay(for: date)
        self.prayerName = prayer.rawValue
    }
}
