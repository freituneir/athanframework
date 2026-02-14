import WidgetKit
import SwiftUI
import AlarmKit

/// Widget bundle for the Athan prayer alarm.
@main
struct AthanWidgetBundle: WidgetBundle {
    var body: some Widget {
        // AlarmKit manages the alarm Live Activity presentation automatically
        // based on the AlarmPresentation configuration provided when scheduling.
        // No custom widget needed - AlarmKit uses the presentation configuration
        // from AlarmSchedulingService.scheduleAlarm()
    }
}
