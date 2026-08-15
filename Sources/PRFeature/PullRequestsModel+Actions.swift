import AgentIDEDomain
import AppKit
import Foundation
import TerminalUI

/// The footer's branch actions, split from the model body for
/// length.
extension PullRequestsModel {
    /// The branch item's worktree with the checked-out branch
    /// substituted, so pushes and pull requests act on what is
    /// actually checked out.
    var actionWorktree: Worktree? {
        guard let item = branchItem else {
            return nil
        }
        guard let currentBranch, currentBranch != item.worktree.branch else {
            return item.worktree
        }

        return Worktree(
            repositoryName: item.worktree.repositoryName,
            repositoryPath: item.worktree.repositoryPath,
            branch: currentBranch,
            path: item.worktree.path,
        )
    }

    /// Copies every unresolved review conversation to the
    /// clipboard, ready for pasting into an agent or reply.
    func copyUnresolvedComments(_ summary: PullRequestSummary) async {
        let threads = await fetchThreads(summary.number).filter { $0.isResolved == false }
        let text = threads.map(\.asText).joined(separator: "\n\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        ErrorLog.shared.note("Copied \(threads.count) unresolved conversations from #\(summary.number).")
    }

    /// Copies the failing checks, one line each, to the clipboard.
    func copyFailingChecks(_ summary: PullRequestSummary) async {
        let text = await fetchFailingChecks(summary.number)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        ErrorLog.shared.note(
            text.isEmpty
                ? "No failing checks on #\(summary.number)."
                : "Copied the failing checks of #\(summary.number).",
        )
    }

    /// The stack size, following base branches that are other listed
    /// pull requests' heads.
    func stackDepth(for summary: PullRequestSummary) -> Int {
        let byHead = Dictionary(summaries.map { ($0.headBranch, $0) }) { first, _ in first }
        var current = summary
        var depth = 1
        var seen = Set([current.headBranch])
        while let next = byHead[current.baseBranch], seen.insert(next.headBranch).inserted {
            depth += 1
            current = next
        }
        return depth
    }

    /// Fills the form's blank fields from the branch's commits: the
    /// one commit's own message when there is only one, otherwise a
    /// draft from the on-device model; false opens the errors
    /// surface. Typed text is never overwritten.
    func generateDescription() async -> Bool {
        guard let worktree = actionWorktree else {
            return false
        }

        let commits = await fetchCommitMessages(worktree)
        guard commits.isEmpty == false else {
            ErrorLog.shared.report("No commits beyond origin/HEAD to describe.")
            return false
        }

        if commits.count == 1, let only = commits.first {
            apply(description: Self.description(splitFromMessage: only))
        } else {
            guard let drafted = await generateDescription(commits) else {
                ErrorLog.shared.report(
                    "The on-device model is unavailable; is Apple Intelligence enabled?",
                )
                return false
            }

            apply(description: drafted)
        }
        // A repository template gets completed from the commits too;
        // an unhelpful or unavailable model leaves it untouched.
        let template = prTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        if template.isEmpty == false, let filled = await fillTemplate(commits, template) {
            prTemplate = filled
        }
        return true
    }

    /// Fills only the blank fields, so typed text always wins.
    func apply(description: (title: String, body: String)) {
        if prTitle.isEmpty {
            prTitle = description.title
        }
        if prBody.isEmpty {
            prBody = description.body
        }
    }

    /// Splits one commit message into the form's title and body.
    static func description(splitFromMessage message: String) -> (title: String, body: String) {
        let lines = message.split(separator: "\n", omittingEmptySubsequences: false)
        let title = lines.first.map(String.init) ?? ""
        let body = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (title, body)
    }

    /// Pushes when needed, then opens the pull request from the
    /// form's title and body, with the template appended below the
    /// body after an empty line; false opens the errors surface.
    func createPullRequest() async -> Bool {
        guard let worktree = actionWorktree else {
            return false
        }

        let title = prTitle.trimmingCharacters(in: .whitespaces)
        guard title.isEmpty == false else {
            ErrorLog.shared.report("The pull request needs a title.")
            return false
        }

        if canPush, await push() == false {
            return false
        }

        let template = prTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = prBody + (template.isEmpty ? "" : "\n\n" + template)
        do {
            let url = try await performCreate(worktree, title, body)
            ErrorLog.shared.note("Opened pull request " + url)
            prTitle = ""
            prBody = ""
            Self.requestSidebarRefresh()
            await reload(keepingSelection: true)
            return true
        } catch {
            ErrorLog.shared.report(error.localizedDescription)
            return false
        }
    }

    /// Pushes the checked-out branch; false means the push failed
    /// and the errors tab should open with the cause.
    func push() async -> Bool {
        guard let worktree = actionWorktree else {
            return true
        }

        do {
            try await performPush(worktree)
            isPushed = true
            status = "Pushed."
            ErrorLog.shared.note("Pushed " + worktree.branch + ".")
            Self.requestSidebarRefresh()
            await reload(keepingSelection: true)
            return true
        } catch {
            ErrorLog.shared.report(error.localizedDescription)
            return false
        }
    }

    /// Rebases onto origin with signed commits; false means the
    /// rebase aborted and the errors tab should open with the cause.
    func rebaseSigned() async -> Bool {
        guard let worktree = actionWorktree else {
            return true
        }

        do {
            try await performRebase(worktree)
            status = "Rebased and signed."
            ErrorLog.shared.note("Rebased and signed " + worktree.branch + ".")
            Self.requestSidebarRefresh()
            await reload(keepingSelection: true)
            return true
        } catch {
            ErrorLog.shared.report(error.localizedDescription)
            return false
        }
    }

    func act(_ work: () async throws -> Void) async {
        do {
            try await work()
            status = "Done."
            await reload(keepingSelection: true)
        } catch {
            ErrorLog.shared.report(error.localizedDescription)
        }
    }

    /// Pokes the sidebar to refresh now rather than on its next
    /// poll, so a push or rebase shows in the counts immediately.
    static func requestSidebarRefresh() {
        let key = "dashboardRefreshRequest"
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: key) + 1, forKey: key)
    }
}
