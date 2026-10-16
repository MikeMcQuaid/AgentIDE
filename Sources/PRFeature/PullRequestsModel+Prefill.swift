import AgentIDEDomain

/// Filling the creation form from a branch's own commits, split from
/// the actions for length.
extension PullRequestsModel {
    /// Explicitly resets the description to the commits, keeping the template.
    func resetToCommits() async {
        guard let worktree = actionWorktree else {
            return
        }

        await prefillFromSingleCommit(worktree, replacing: true)
    }

    /// Refreshes automatic defaults until the description has meaningful edits.
    func prefillFromSingleCommit(_ worktree: Worktree, replacing: Bool = false) async {
        guard replacing || canRefreshDescription else {
            return
        }

        let key = draftKey
        let title = prTitle
        let body = prBody
        let commits = await fetchCommitMessages(worktree, listedRange)
        guard key == draftKey, title == prTitle, body == prBody,
              replacing || canRefreshDescription, let first = commits.first
        else {
            return
        }

        var description = Self.description(splitFromMessage: first)
        if commits.count > 1 {
            description.body = commits.dropFirst()
                .map { "- " + Self.description(splitFromMessage: $0).title }
                .joined(separator: "\n")
        }
        loadingDraft = true
        apply(description: description, replacing: true)
        loadingDraft = false
        saveDraft(defaults: description)
    }

    private var canRefreshDescription: Bool {
        guard editingNumber == nil, let branch = listedBranch, hasOpenPullRequest(branch) == false else {
            return false
        }

        let draft = draftKey.flatMap { store.load().pullRequestDrafts[$0] }
        return zip([prTitle, prBody], [draft?.defaultTitle ?? "", draft?.defaultBody ?? ""]).allSatisfy { text, saved in
            text.filter { $0.isWhitespace == false } == saved.filter { $0.isWhitespace == false }
        }
    }

    /// Whether a field holds nothing to lose: empty, or whitespace
    /// alone.
    static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Fills only the blank fields, so typed text always wins.
    func apply(description: (title: String, body: String), replacing: Bool = false) {
        if replacing || Self.isBlank(prTitle) {
            prTitle = description.title
        }
        if replacing || Self.isBlank(prBody) {
            prBody = description.body
        }
    }

    /// Splits one commit message into the form's title and body.
    /// The body comes back unwrapped: commit messages are wrapped by
    /// hand to a narrow column, and a pull request reflows its own
    /// text, so the hand-wrapping reads as broken bullets there.
    static func description(splitFromMessage message: String) -> (title: String, body: String) {
        let lines = message.split(separator: "\n", omittingEmptySubsequences: false)
        let title = lines.first.map(String.init) ?? ""
        let body = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (title, Wrapping.unwrapped(body))
    }
}
