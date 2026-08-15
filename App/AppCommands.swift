import DashboardFeature
import SwiftUI

/// The app's menus: session and repository creation replace the
/// stock New Window item, and View gains the utility pane, its tabs
/// and the finder shortcuts.
struct AppCommands: Commands {
    // MARK: Internal

    let dashboard: DashboardModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Agent Session") {
                // No preset: the menu is repository-agnostic, and a
                // stale preset would lock the picker.
                dashboard.newSessionRepository = nil
                dashboard.showsNewSession = true
            }
            .keyboardShortcut("n", modifiers: .command)
            Button("Open Repository…") { dashboard.showsRepositoryFinder = true }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Divider()
            Button("Manage Sessions…") { dashboard.showsSessionManager = true }
        }
        CommandMenu("Worktree") {
            Button("Push") { bump("pushRequest") }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Button("Rebase on Origin") { bump("rebaseRequest") }
                .keyboardShortcut("r", modifiers: [.command, .option])
            Button("Commit Outstanding") { bump("commitRequest") }
                .keyboardShortcut("k", modifiers: [.command, .option])
            Divider()
            Button("Refresh") { bump("dashboardRefreshRequest") }
                .keyboardShortcut("r", modifiers: .command)
        }
        CommandGroup(after: .sidebar) {
            // The repository sidebar never hides, only resizes, so
            // the utility pane is the one toggle here.
            Button(showsUtilityPane ? "Hide Utility Pane" : "Show Utility Pane") {
                showsUtilityPane.toggle()
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])
            Divider()
            ForEach(Array(UtilityTab.allCases.enumerated()), id: \.element) { index, tab in
                Button(tab.title) { show(tab) }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            }
            Divider()
            Button("Find File") { openFinder(searchingContents: false) }
                .keyboardShortcut("t", modifiers: .command)
            Button("Search File Contents") { openFinder(searchingContents: true) }
                .keyboardShortcut("f", modifiers: [.command, .shift])
        }
    }

    // MARK: Private

    @AppStorage("showsUtilityPane")
    private var showsUtilityPane = true
    @AppStorage("utilityTab")
    private var utilityTab = UtilityTab.review.rawValue
    @AppStorage("finderSearchesContents")
    private var finderSearchesContents = false
    @AppStorage("finderFocusRequest")
    private var finderFocusRequest = 0

    /// Increments a storage-bus counter; the pane owning the
    /// action observes it and runs.
    private func bump(_ key: String) {
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: key) + 1, forKey: key)
    }

    private func show(_ tab: UtilityTab) {
        showsUtilityPane = true
        utilityTab = tab.rawValue
    }

    /// Jumps to the editor tab's finder in the chosen mode; the pane
    /// consumes the focus request once it is on screen.
    private func openFinder(searchingContents: Bool) {
        show(.editor)
        finderSearchesContents = searchingContents
        finderFocusRequest += 1
    }
}
