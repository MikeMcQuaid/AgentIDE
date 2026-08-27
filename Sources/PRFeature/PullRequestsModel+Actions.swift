import AgentIDEData
import AgentIDEDomain
import AppKit
import Foundation
import TerminalUI

/// The footer's branch actions, split from the model body for
/// length.
extension PullRequestsModel {
    /// What the worktree itself says: its stack, signing, rebase
    /// need, template and checked-out branch. Skipped when moving
    /// between a stack's entries, which share all of it.
    func refreshWorktreeFacts(_ worktree: Worktree) async {
        await loadStack()
        isTipSigned = await checkTipSigned(listedWorktree ?? worktree)
        rebaseNeed = await fetchRebaseNeed(worktree)
        let template = await fetchTemplate(worktree.path)
        hasTemplate = template != nil
        originalTemplate = template ?? ""
        if prTemplate.isEmpty {
            prTemplate = originalTemplate
        }
        await prefillFromSingleCommit(worktree)
        if let live = await fetchCurrentBranch(worktree.path) {
            currentBranch = live
        }
    }

    /// Refreshes one pull request's header wherever it shows, so
    /// actions like resolving conversations reflect immediately in
    /// the selected conversation and its listed row.
    func refreshSummary(_ number: Int) async {
        guard let full = try? await fetchSummary(number) else {
            return
        }

        cacheEnriched(full)
        if selected?.number == number {
            selected = full
        }
        if let index = summaries.firstIndex(where: { $0.number == number }) {
            summaries[index] = full
        }
    }

    /// Shows a status in the footer and keeps it in the messages
    /// pane, where a line that scrolls past can still be read.
    /// `detail` is what the messages pane keeps when the footer's
    /// wording is too terse to mean anything later; without it the
    /// footer's own line is kept, once.
    func setStatus(_ message: String, detail: String? = nil) {
        status = message
        ErrorLog.shared.note(detail ?? message)
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

    /// Jumps to the one failing check, or to the checks page when
    /// several fail or the row has not been enriched with their
    /// links yet; copying their logs proved too unreliable to trust.
    func openFailingChecks(_ summary: PullRequestSummary) {
        let links = summary.failingCheckLinks
        LinkOpener.open(links.count == 1 ? links[0] : summary.url + "/checks")
    }

    /// Opens a conversation with its cached enriched header painted
    /// instantly, then refreshes it; the open scope's light rows
    /// gain their status icons here.
    func select(_ summary: PullRequestSummary) {
        selected = pullRequests.cachedSummary(repositoryPath: repository.path, number: summary.number)
            ?? summary
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
        pullRequests.rememberSummary(repositoryPath: repository.path, summary: summary)
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

    /// Fills the form's blank fields from the branch's commits: the
    /// one commit's own message when there is only one, otherwise a
    /// draft from the on-device model; false opens the errors
    /// surface. Typed text is never overwritten.
    func generateDescription() async -> Bool {
        guard let worktree = actionWorktree else {
            return false
        }

        let commits = await fetchCommitMessages(worktree, listedRange)
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

    /// What a push is reported as, which depends on where it went:
    /// a branch that went to a fork is worth saying so about, since
    /// it is not in the repository being looked at.
    static func describe(push destination: PushDestination, branch: String) -> String {
        guard case let .fork(owner) = destination else {
            return "Pushed " + branch + "."
        }

        return "Pushed " + branch + " to " + owner + "'s fork, since this repository is not yours to push to."
    }

    /// Opens the pull request from the form's title and body, with
    /// the template appended below the body after an empty line;
    /// false opens the errors surface. The button dims until the
    /// branch is pushed, so nothing pushes implicitly here.
    func createPullRequest() async -> Bool {
        guard let worktree = listedWorktree else {
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
            pullRequests.invalidateListings(repositoryPath: repository.path)
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
        guard let worktree = listedWorktree else {
            return true
        }

        do {
            let destination = try await performPush(worktree)
            pullRequests.invalidateListings(repositoryPath: repository.path)
            isPushed = true
            setStatus("Pushed.", detail: Self.describe(push: destination, branch: worktree.branch))
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
