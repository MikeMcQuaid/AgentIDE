import AppKit
import SwiftUI
import TerminalUI

// MARK: - AppDelegate

/// Quits the app when its last window closes. Everything that must
/// survive lives outside the process: herdr sessions and their
/// agents keep running, and the event spool holds notifications for
/// the next launch. A windowless AgentIDE polled nothing and
/// delivered nothing, so staying resident was a dead app.
final class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: Lifecycle

    deinit {
        // Lives for the app's whole lifetime.
    }

    // MARK: Internal

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }
}

// MARK: - AgentIDEApp

@main
struct AgentIDEApp: App {
    // MARK: Lifecycle

    init() {
        // A single-window app: disabling window tabs also removes the
        // stock Show Tab Bar and Show All Tabs items from View.
        NSWindow.allowsAutomaticWindowTabbing = false
        // Every field here holds code, a commit message or a pull
        // request body, and text substitution turns quotes into
        // curly ones and double dashes into em dashes in all of
        // them. The app's own defaults turn it off for the SwiftUI
        // fields, whose text views it cannot otherwise reach; the
        // code editor sets the same switches on itself.
        for key in [
            "NSAutomaticQuoteSubstitutionEnabled",
            "NSAutomaticDashSubstitutionEnabled",
            "NSAutomaticTextReplacementEnabled",
            "NSAutomaticSpellingCorrectionEnabled",
            "NSAutomaticCapitalizationEnabled",
            "NSAutomaticPeriodSubstitutionEnabled",
        ] {
            UserDefaults.standard.set(false, forKey: key)
        }
    }

    // MARK: Internal

    /// Installs `AppDelegate`, which quits the app when its last
    /// window closes. Internal, not private: nothing references it,
    /// so the formatter's unused-private-declaration rule silently
    /// deleted a private one, and the delegate with it.
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    var delegate

    var body: some Scene {
        WindowGroup {
            RootView(dependencies: dependencies)
                .environment(\.openURL, LinkOpener.action)
        }

        // Content over chrome: no title bar, compact toolbar.
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands { AppCommands(dashboard: dependencies.dashboard) }
    }

    // MARK: Private

    private let dependencies: AppDependencies = .init()
}
