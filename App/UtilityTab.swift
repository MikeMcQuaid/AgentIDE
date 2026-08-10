/// The tabs of the utility pane beside the agent.
enum UtilityTab: CaseIterable {
    case shell
    case review
    case pullRequests
    case editor
    case browser
    case message

    // MARK: Internal

    var title: String {
        switch self {
        case .shell:
            "Shell"

        case .review:
            "Review"

        case .pullRequests:
            "PRs"

        case .editor:
            "Editor"

        case .browser:
            "Browser"

        case .message:
            "Summary"
        }
    }

    var help: String {
        switch self {
        case .shell:
            "A host-user shell in this worktree; it runs in host tmux, so it survives tab switches and app restarts"

        case .review:
            "The worktree's diff with per-line rejection and commit message editing"

        case .pullRequests:
            "Open pull requests for this worktree's branch, with review comments and check results"

        case .editor:
            "Find files fuzzily or search contents with ripgrep, then edit them in place"

        case .browser:
            "An embedded browser for dev servers the agent starts and pull request pages; logins persist"

        case .message:
            "The agent's last reply as text, plus the session actions: commit leftover work, close, resume, push and PR"
        }
    }
}
