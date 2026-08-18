import WidgetKit
import SwiftUI

@main
struct RemindersCompanionWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        NextUpWidget()
    }
}
