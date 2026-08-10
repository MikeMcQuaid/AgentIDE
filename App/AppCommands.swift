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
            Button("New Agent Session") { dashboard.showsNewSession = true }
                .keyboardShortcut("n", modifiers: .command)
            Button("Open Repository…") { dashboard.showsRepositoryFinder = true }
                .keyboardShortcut("o", modifiers: [.command, .shift])
        }
        CommandGroup(after: .sidebar) {
            // The two panes toggle together in one group.
            Button(showsRepositorySidebar ? "Hide Repository Sidebar" : "Show Repository Sidebar") {
                showsRepositorySidebar.toggle()
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
            Button(showsUtilityPane ? "Hide Utility Pane" : "Show Utility Pane") {
                showsUtilityPane.toggle()
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])
            Divider()
            ForEach(Array(UtilityTab.allCases.enumerated()), id: \.element) { index, tab in
                Button(tab.title) { show(tabAt: index) }
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

    @AppStorage("showsRepositorySidebar")
    private var showsRepositorySidebar = true
    @AppStorage("showsUtilityPane")
    private var showsUtilityPane = true
    @AppStorage("utilityTabIndex")
    private var utilityTabIndex = 0
    @AppStorage("finderSearchesContents")
    private var finderSearchesContents = false
    @AppStorage("finderFocusRequest")
    private var finderFocusRequest = 0

    private func show(tabAt index: Int) {
        showsUtilityPane = true
        utilityTabIndex = index
    }

    /// Jumps to the editor tab's finder in the chosen mode; the pane
    /// consumes the focus request once it is on screen.
    private func openFinder(searchingContents: Bool) {
        showsUtilityPane = true
        utilityTabIndex = UtilityTab.allCases.firstIndex(of: .editor) ?? 0
        finderSearchesContents = searchingContents
        finderFocusRequest += 1
    }
}
