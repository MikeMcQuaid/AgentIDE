import AgentIDEData
import SwiftUI
import TerminalUI

// MARK: - PullRequestScope

/// Which pull requests the tab lists.
enum PullRequestScope: CaseIterable {
    case worktree
    case mine
    case open

    // MARK: Internal

    var title: String {
        switch self {
        case .worktree:
            "Worktree"

        case .mine:
            "Mine"

        case .open:
            "Open"
        }
    }

    /// The client's scope, branch-bound for the worktree case.
    func listScope(branch: String?) -> GitHubClient.ListScope {
        switch self {
        case .worktree:
            .branch(branch ?? "")

        case .mine:
            .mine

        case .open:
            .open
        }
    }
}

// MARK: - PullRequestScopePicker

/// The segmented scope control at the tab's top.
struct PullRequestScopePicker: View {
    // MARK: Internal

    @Binding var scope: PullRequestScope

    /// What the worktree scope calls itself: Branch on the main
    /// checkout, where there is no worktree to speak of.
    let worktreeTitle: String

    var body: some View {
        Picker("Scope", selection: $scope) {
            ForEach(PullRequestScope.allCases, id: \.self) { scope in
                Text(scope == .worktree ? worktreeTitle : scope.title).tag(scope)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .labelsHidden()
        .padding(Self.padding)
        .hoverHelp(
            "Worktree: this branch's pull requests, open and closed. Mine: open ones you created. Open: every open one",
        )
    }

    // MARK: Private

    private static let padding: CGFloat = 8
}
