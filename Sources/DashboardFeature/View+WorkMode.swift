import AppKit
import SwiftUI

extension View {
    func workModeUpdates(_ model: DashboardModel) -> some View {
        onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            model.refreshWorkMode(onlyIfSettingsChanged: true)
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
            model.refreshWorkMode()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name.NSSystemTimeZoneDidChange)) { _ in
            model.refreshWorkMode()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name.NSSystemClockDidChange)) { _ in
            model.refreshWorkMode()
        }
    }
}
