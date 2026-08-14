/// The tabs of the utility pane beside the agent. The raw values
/// are the persisted selection and the cross-module signal values,
/// so reordering cases can never repoint a saved tab the way the
/// old stored indices did.
enum UtilityTab: String, CaseIterable {
    // The case names are the persisted values (SwiftFormat strips
    // explicit raw values), so renaming a case renames what is
    // stored: keep names stable or migrate deliberately.
    // swiftlint:disable explicit_enum_raw_value
    case review
    case pullRequests
    case browser
    case editor
    case shell
    case errors
    // swiftlint:enable explicit_enum_raw_value

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

        case .errors:
            "Errors"
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

        case .errors:
            "Every failure reported this session, in full and copyable; appears on the first error"
        }
    }
}
