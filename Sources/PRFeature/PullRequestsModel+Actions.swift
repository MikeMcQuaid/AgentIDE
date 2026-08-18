import AgentIDEData
import AgentIDEDomain
import AppKit
import Foundation
import TerminalUI

/// The footer's branch actions, split from the model body for
/// length.
extension PullRequestsModel {
    /// Shows a status in the footer and keeps it in the messages
    /// pane, where a line that scrolls past can still be read.
    /// `detail` is what the messages pane keeps when the footer's
    /// wording is too terse to mean anything later; without it the
    /// footer's own line is kept, once.
    func setStatus(_ message: String, detail: String? = nil) {
        status = message
        ErrorLog.shared.note(detail ?? message)
    }

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

    /// Opens a conversation with its cached enriched header painted
    /// instantly, then refreshes it; the open scope's light rows
    /// gain their status icons here.
    func select(_ summary: PullRequestSummary) {
        selected = store.load().enrichedSummaryCache[enrichedKey(summary.number)]?.summary ?? summary
        Task {
            let full = try? await fetchSummary(summary.number)
            if let full {
                cacheEnriched(full)
                if selected?.number == full.number {
                    selected = full
                }
            }
        }
    }

    /// Caches one enriched summary, so reopening the conversation
    /// or restarting the app paints its header instantly.
    func cacheEnriched(_ summary: PullRequestSummary) {
        var metadata = store.load()
        metadata.enrichedSummaryCache[enrichedKey(summary.number)] = CachedSummary(summary: summary)
        store.save(metadata)
    }

    /// The enriched summary cache key for one pull request.
    func enrichedKey(_ number: Int) -> String {
        repository.path + "#" + String(number)
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

    /// Whether every local commit is already on the upstream; Open
    /// PR stays dimmed until then.
    var isFullyPushed: Bool {
        isPushed || branchItem?.aheadOfUpstream == 0
    }

    /// A one-commit branch is its own description: the form
    /// defaults to that commit, no model involved.
    func prefillFromSingleCommit(_ worktree: Worktree) async {
        guard prTitle.isEmpty, prBody.isEmpty else {
            return
        }

        let commits = await fetchCommitMessages(worktree)
        if commits.count == 1, let only = commits.first {
            apply(description: Self.description(splitFromMessage: only))
        }
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
    /// The body comes back unwrapped: commit messages are wrapped by
    /// hand to a narrow column, and a pull request reflows its own
    /// text, so the hand-wrapping reads as broken bullets there.
    static func description(splitFromMessage message: String) -> (title: String, body: String) {
        let lines = message.split(separator: "\n", omittingEmptySubsequences: false)
        let title = lines.first.map(String.init) ?? ""
        let body = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (title, Wrapping.unwrapped(body))
    }

    /// Opens the pull request from the form's title and body, with
    /// the template appended below the body after an empty line;
    /// false opens the errors surface. The button dims until the
    /// branch is pushed, so nothing pushes implicitly here.
    func createPullRequest() async -> Bool {
        guard let worktree = actionWorktree else {
            return false
        }

        let title = prTitle.trimmingCharacters(in: .whitespaces)
        guard title.isEmpty == false else {
            ErrorLog.shared.report("The pull request needs a title.")
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
            clearDraft()
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
            setStatus("Pushed.", detail: "Pushed " + worktree.branch + ".")
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
            setStatus("Rebased and signed.", detail: "Rebased and signed " + worktree.branch + ".")
            Self.requestSidebarRefresh()
            await reload(keepingSelection: true)
            return true
        } catch {
            ErrorLog.shared.report(error.localizedDescription)
            return false
        }
    }

    /// The one merge action's label, naming exactly what a click
    /// does right now; nil when no open conversation is selected.
    var mergeActionTitle: String? {
        guard let selected, selected.state == "OPEN" else {
            return nil
        }

        if selected.hasAutomerge {
            return hasMergeQueue ? "Dequeue" : "Cancel automerge"
        }
        if selected.checks == "SUCCESS", selected.mergeable == "MERGEABLE" {
            return hasMergeQueue ? "Queue" : "Merge"
        }
        return "Automerge"
    }

    /// The present-tense form while the merge action runs.
    var mergeActionBusyTitle: String {
        switch mergeActionTitle {
        case "Dequeue":
            "Dequeuing"

        case "Cancel automerge":
            "Cancelling"

        case "Queue":
            "Queueing"

        case "Merge":
            "Merging"

        default:
            "Enabling automerge"
        }
    }

    /// Merges, queues, enables automerge or cancels either, per the
    /// label; an immediate merge from the main checkout also cleans
    /// the checkout up, returning to the default branch and deleting
    /// the merged one. The header refreshes to show the new state.
    func performMergeAction() async {
        guard let selected, selected.state == "OPEN" else {
            return
        }

        let merges = selected.hasAutomerge == false
            && selected.checks == "SUCCESS" && selected.mergeable == "MERGEABLE"
        let succeeded = await act { try await performMergeChange(selected) }
        if succeeded, merges, let worktree = actionWorktree {
            await performPostMergeCleanup(worktree, selected.headBranch)
        }
        await refreshSummary(selected.number)
    }

    @discardableResult
    func act(_ work: () async throws -> Void) async -> Bool {
        do {
            try await work()
            setStatus("Done.")
            await reload(keepingSelection: true)
            return true
        } catch {
            ErrorLog.shared.report(error.localizedDescription)
            return false
        }
    }

    /// Pokes the sidebar to refresh now rather than on its next
    /// poll, so a push or rebase shows in the counts immediately.
    static func requestSidebarRefresh() {
        let key = "dashboardRefreshRequest"
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: key) + 1, forKey: key)
    }
}
