import SwiftUI

/// Connects Settings actions and schedule wake-ups to the main window.
struct SettingsEvents: ViewModifier {
    // MARK: Internal

    let dependencies: AppDependencies
    let onCloseBrowser: (String) -> Void

    func body(content: Content) -> some View {
        content
            .task { await dependencies.schedules.runDue() }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemClockDidChange)) { _ in
                Task { await dependencies.schedules.runDue() }
            }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
                Task { await dependencies.schedules.runDue() }
            }
            .onChange(of: closeBrowserRequest) {
                onCloseBrowser(UserDefaults.standard.string(forKey: "closeBrowserPath") ?? "")
            }
    }

    // MARK: Private

    @AppStorage("closeBrowserRequest")
    private var closeBrowserRequest = 0
}
