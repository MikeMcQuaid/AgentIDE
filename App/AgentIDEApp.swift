import AppKit
import SwiftUI

@main
struct AgentIDEApp: App {
    // MARK: Lifecycle

    init() {
        // A single-window app: disabling window tabs also removes the
        // stock Show Tab Bar and Show All Tabs items from View.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    // MARK: Internal

    var body: some Scene {
        WindowGroup {
            RootView(dependencies: dependencies)
        }
        // Content over chrome: no title bar, compact toolbar.
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands { AppCommands(dashboard: dependencies.dashboard) }
    }

    // MARK: Private

    private let dependencies: AppDependencies = .init()
}
