import Foundation
import SwiftData

/// Device-local mapping between prayers and their active AlarmKit alarm IDs.
/// Stored in a LOCAL-ONLY ModelConfiguration (never synced to iCloud) because
/// AlarmKit alarms are device-specific — each device schedules its own alarms.
@Model
final class DeviceAlarmState {
    var prayerName: String = ""

    /// The UUID passed to `AlarmManager.shared.schedule(id:configuration:)`.
    /// Used to cancel or reschedule the alarm.
    var alarmID: UUID?

    /// Tracks which device this state belongs to (UIDevice.current.identifierForVendor).
    var deviceID: String = ""

    /// When this alarm was last scheduled.
    var lastScheduled: Date?

    /// When this alarm is set to fire.
    var fireDate: Date?

    init() {}

    convenience init(prayerName: String, alarmID: UUID, deviceID: String, fireDate: Date? = nil) {
        self.init()
        self.prayerName = prayerName
        self.alarmID = alarmID
        self.deviceID = deviceID
        self.lastScheduled = Date()
        self.fireDate = fireDate
    }
}
