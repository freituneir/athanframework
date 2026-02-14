import WidgetKit
import SwiftUI
import AlarmKit

/// Widget bundle for Athan alarm Live Activities.
@main
struct AthanWidgetBundle: WidgetBundle {
    var body: some Widget {
        AthanAlarmLiveActivity()
        ReminderAlarmLiveActivity()
    }
}
