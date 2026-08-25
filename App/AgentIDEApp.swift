import AppKit
import SwiftUI
import TerminalUI

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

    /// What a first run opens at; a saved frame wins over it.
    static let defaultWidth: CGFloat = 1_600
    static let defaultHeight: CGFloat = 1_000

    var body: some Scene {
        WindowGroup {
            RootView(dependencies: dependencies)
                .environment(\.openURL, LinkOpener.action)
        }
        // The saved frame wins; this is what a first run opens at.
        .defaultSize(width: Self.defaultWidth, height: Self.defaultHeight)
        // Content over chrome: no title bar, compact toolbar.
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands { AppCommands(dashboard: dependencies.dashboard) }
    }

    // MARK: Private

    private let dependencies: AppDependencies = .init()
}
