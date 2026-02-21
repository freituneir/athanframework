import WidgetKit
import SwiftUI
import AlarmKit
import ActivityKit

/// Widget bundle for Athan alarm Live Activities + standalone Pray Now LA.
@main
struct AthanWidgetBundle: WidgetBundle {
    var body: some Widget {
        AthanAlarmLiveActivity()
        ReminderAlarmLiveActivity()
        PrayNowLiveActivity()
        PrayerTimesWidget()
    }
}
