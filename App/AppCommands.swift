import AppKit
import DashboardFeature
import SwiftUI

/// The app's menus: session and repository creation replace the
/// stock New Window item, and View gains the utility pane, its tabs
/// and the finder shortcuts.
struct AppCommands: Commands {
    // MARK: Internal

    let dashboard: DashboardModel

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            // The version already ends in the build number, so the
            // panel's own build field would say it twice.
            Button("About AgentIDE") {
                NSApplication.shared.orderFrontStandardAboutPanel(options: [.version: ""])
            }
        }
        CommandGroup(replacing: .newItem) {
            Button("New Agent Session") {
                // No preset: the menu is repository-agnostic, and a
                // stale preset would lock the picker.
                dashboard.openNewSession(for: nil)
            }
            .keyboardShortcut("n", modifiers: .command)
            Button("Open Repository…") { dashboard.showsRepositoryFinder = true }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Divider()
            Button("Manage Sessions…") { dashboard.showsSessionManager = true }
        }
        CommandMenu("Worktree") {
            Button("Clear Shell") { clearShellRequest += 1 }
                .keyboardShortcut("k", modifiers: .command)
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
        CommandGroup(after: .textEditing) {
            Button("Find…") { find(.showFindInterface) }
                .keyboardShortcut("f", modifiers: .command)
            Button("Find Next") { find(.nextMatch) }
                .keyboardShortcut("g", modifiers: .command)
            Button("Find Previous") { find(.previousMatch) }
                .keyboardShortcut("g", modifiers: [.command, .shift])
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
            Button("Resize Panes") { resizePanesRequest += 1 }
                .keyboardShortcut("0", modifiers: .command)
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

    /// Cmd-0's counter: the window narrows the sidebar to what its
    /// rows need and splits the rest evenly.
    @AppStorage("resizePanesRequest")
    private var resizePanesRequest = 0

    /// Cmd-K's counter: the active shell pane clears once per raise;
    /// agent panes ignore it.
    @AppStorage("clearShellRequest")
    private var clearShellRequest = 0

    /// Increments a storage-bus counter; the pane owning the
    /// action observes it and runs.
    private func bump(_ key: String) {
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: key) + 1, forKey: key)
    }

    /// Finding goes to whatever is focused: the editor and the
    /// terminals answer AppKit's standard action, and the review
    /// pane, which is a list of views rather than a text view, gets
    /// the request through the storage bus when nothing else took it.
    private func find(_ action: NSTextFinder.Action) {
        let item = NSMenuItem()
        item.tag = action.rawValue
        guard NSApp.sendAction(
            #selector(NSResponder.performTextFinderAction(_:)),
            to: nil,
            from: item,
        ) == false else {
            return
        }

        switch action {
        case .nextMatch:
            bump("reviewFindNextRequest")

        case .previousMatch:
            bump("reviewFindPreviousRequest")

        default:
            bump("reviewFindRequest")
        }
    }

    private func show(_ tab: UtilityTab) {
        showsUtilityPane = true
        utilityTab = tab.rawValue
    }

    /// Asks for an editor finder in the chosen mode; the window
    /// routes the request to the centre or side editor, reveals it
    /// and its pane consumes the focus once on screen.
    private func openFinder(searchingContents: Bool) {
        finderSearchesContents = searchingContents
        finderFocusRequest += 1
    }
}
