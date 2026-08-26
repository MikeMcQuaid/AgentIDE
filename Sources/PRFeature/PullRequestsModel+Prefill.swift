import AgentIDEDomain
import Foundation

/// Filling the creation form from a branch's own commits, split from
/// the actions for length.
extension PullRequestsModel {
    /// A one-commit branch is its own description: the form
    /// defaults to that commit, no model involved. Blank is blank
    /// however it got that way, whitespace included, so a saved
    /// draft holding nothing is no reason to leave the form empty.
    func prefillFromSingleCommit(_ worktree: Worktree) async {
        guard Self.isBlank(prTitle), Self.isBlank(prBody) else {
            return
        }

        let commits = await fetchCommitMessages(worktree, listedRange)
        if commits.count == 1, let only = commits.first {
            apply(description: Self.description(splitFromMessage: only))
        } else if let first = commits.first {
            // Several commits: the first one's subject titles the
            // pull request and the rest list the body, which is what
            // Submit stack writes for a stack entry.
            let subjects = commits.map { Self.description(splitFromMessage: $0).title }
            let rest = subjects.dropFirst().map { "- " + $0 }.joined(separator: "\n")
            apply(description: (Self.description(splitFromMessage: first).title, rest))
        }
    }

    /// Whether a field holds nothing to lose: empty, or whitespace
    /// alone.
    static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Fills only the blank fields, so typed text always wins.
    func apply(description: (title: String, body: String)) {
        if Self.isBlank(prTitle) {
            prTitle = description.title
        }
        if Self.isBlank(prBody) {
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
