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
        // Gather, then write only while still the newest read: an
        // older reload landing stale signing facts over the rebase's
        // fresh ones is how Push sometimes stayed locked until a
        // second press ran a fresh read.
        stacking.factsGeneration += 1
        let generation = stacking.factsGeneration
        let signed = await checkTipSigned(listedWorktree ?? worktree)
        let need = await fetchRebaseNeed(listedWorktree ?? worktree)
        let template = await fetchTemplate(worktree.path)
        let live = await fetchCurrentBranch(worktree.path)
        let labels = availableLabels.isEmpty ? await fetchLabels() : availableLabels
        guard generation == stacking.factsGeneration else {
            return
        }

        isTipSigned = signed
        rebaseNeed = need
        availableLabels = labels
        hasTemplate = template != nil
        originalTemplate = template ?? ""
        if prTemplate.isEmpty {
            prTemplate = originalTemplate
        }
        await prefillFromSingleCommit(worktree)
        if let branch = live {
            currentBranch = branch
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
            selected = withCachedUnresolved(full)
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
        note(detail ?? message)
    }

    /// How long a push waits before looking again. Asking at once
    /// answers with the checks as they were before it: GitHub takes
    /// a moment to see the new commits, and the store would then
    /// hold that stale answer for a minute more. A minute later the
    /// run has been created and the row goes yellow.
    static let checksDelay: Duration = .seconds(PullRequestStore.minimumInterval)

    /// Looks at the branch's pull request again a minute after a
    /// push, from the store's own timers outwards, so the row and
    /// the header catch the checks the push started.
    func refreshAfterPush() {
        Task { [weak self] in
            try? await Task.sleep(for: Self.checksDelay)
            guard let self, Task.isCancelled == false else {
                return
            }

            pullRequests.invalidateListings(repositoryPath: repository.path)
            if let number = selected?.number {
                pullRequests.invalidate(repositoryPath: repository.path, number: number)
            }
            Self.requestSidebarRefresh()
            await reload(keepingSelection: true)
        }
    }

    /// A note about this repository's work, named as the sidebar
    /// names it.
    func note(_ message: String) {
        ErrorLog.shared.note(message, about: repository.name)
    }

    /// The same for a failure.
    func report(_ message: String) {
        ErrorLog.shared.report(message, about: repository.name)
    }

    /// Copies every unresolved review conversation to the
    /// clipboard, ready for pasting into an agent or reply.
    func copyUnresolvedComments(_ summary: PullRequestSummary) async {
        let threads = await fetchThreads(summary.number).filter { $0.isResolved == false }
        let text = ReviewThread.digest(of: threads)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        note("Copied \(threads.count) unresolved conversations from #\(summary.number).")
    }

    /// Jumps to the one failing check, or to the checks page when
    /// several fail or the row has not been enriched with their
    /// links yet; the logs themselves copy from the button beside.
    func openFailingChecks(_ summary: PullRequestSummary) {
        let links = summary.failingCheckLinks
        LinkOpener.open(links.count == 1 ? links[0] : summary.url + "/checks")
    }

    /// Opens a conversation with its cached enriched header painted
    /// instantly, then refreshes it; the open scope's light rows
    /// gain their status icons here.
    func select(_ summary: PullRequestSummary) {
        let cached = pullRequests.cachedSummary(repositoryPath: repository.path, number: summary.number)
        selected = withCachedUnresolved(cached ?? summary)
        Task { await loadSelectedLabels(summary.number) }
        Task {
            let full = try? await fetchSummary(summary.number)
            if let full {
                cacheEnriched(full)
                if selected?.number == full.number {
                    selected = withCachedUnresolved(full)
                }
            }
        }
    }

    /// The conversation pane counted its unresolved threads: keep
    /// the open summary level with it, which is what enables the
    /// footer's copy button the moment there is something to copy.
    func updateUnresolved(_ count: Int, number: Int) {
        guard selected?.number == number else {
            return
        }

        selected?.unresolvedComments = count
    }

    /// A summary with its unresolved-conversation count from the
    /// threads cache: no listing or summary query carries the count,
    /// so what the conversation pane last cached stands in, the way
    /// the sidebar rows count theirs.
    private func withCachedUnresolved(_ summary: PullRequestSummary) -> PullRequestSummary {
        let key = AppMetadata.threadsKey(repositoryPath: repository.path, number: summary.number)
        let threads = store.load().threadsCache[key]?.threads ?? []
        var stamped = summary
        stamped.unresolvedComments = threads.count { $0.isResolved == false }
        return stamped
    }

    /// Caches one enriched summary, so reopening the conversation
    /// or restarting the app paints its header instantly.
    func cacheEnriched(_ summary: PullRequestSummary) {
        let before = pullRequests.cachedSummary(repositoryPath: repository.path, number: summary.number)
        pullRequests.rememberSummary(repositoryPath: repository.path, summary: summary)
        // The sidebar's row reads this same cache; a changed state
        // tells it to look again now, not on its next poll.
        if before.map({ Self.state(of: $0) }) != Self.state(of: summary) {
            let key = UtilityTabTarget.pullRequestCacheKey
            UserDefaults.standard.set(UserDefaults.standard.integer(forKey: key) + 1, forKey: key)
        }
    }

    /// What the sidebar's row colours from, so only a change in it
    /// asks the sidebar to repaint.
    static func state(of summary: PullRequestSummary) -> [String] {
        [summary.checks, summary.state, summary.mergeable, summary.reviewDecision, String(summary.isDraft)]
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

    /// Fills the form from the branch's commits: the one commit's own
    /// message when there is only one, otherwise a draft from the
    /// on-device model given the branch name and every message; false
    /// opens the errors surface. Blank fields fill either way; typed
    /// text is replaced only when `replacing`, which the form asks
    /// about first.
    func generateDescription(replacing: Bool = false) async -> Bool {
        guard let worktree = actionWorktree else {
            return false
        }

        let commits = await fetchCommitMessages(worktree, listedRange)
        guard commits.isEmpty == false else {
            report("No commits beyond origin/HEAD to describe.")
            return false
        }

        if commits.count == 1, let only = commits.first {
            apply(description: Self.description(splitFromMessage: only), replacing: replacing)
        } else {
            guard let drafted = await generateDescription(commits, listedBranch ?? worktree.branch) else {
                report(
                    "The on-device model is unavailable; is Apple Intelligence enabled?",
                )
                return false
            }

            apply(description: drafted, replacing: replacing)
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
            report("The pull request needs a title.")
            return false
        }

        let template = prTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = prBody + (template.isEmpty ? "" : "\n\n" + template)
        isOpening = true
        defer { isOpening = false }
        do {
            let url = try await performCreate(worktree, title, body, prLabels)
            note("Opened pull request " + url)
            // A stack is built one pull request at a time: each one
            // links what is open into the stack, and failing to link
            // never takes the pull request that opened with it.
            do {
                try await performLinkStack(worktree)
            } catch {
                report("Stacking on GitHub failed: " + error.localizedDescription)
            }
            pullRequests.invalidateListings(repositoryPath: repository.path)
            Self.requestSidebarRefresh()
            await reload(keepingSelection: true)
            // Straight into what was just opened: the listing has it
            // by number, and its conversation is what the form was
            // for. Only once it is showing does the form let go of
            // the text, so nothing blank is ever on screen.
            let opened = Self.number(inURL: url)
            if let summary = summaries.first(where: { $0.number == opened }) {
                select(summary)
            }
            loadingDraft = true
            prTitle = ""
            prLabels = []
            prBody = ""
            prTemplate = originalTemplate
            loadingDraft = false
            clearDraft()
            return true
        } catch {
            report(error.localizedDescription)
            return false
        }
    }

    /// Pushes the checked-out branch; false means the push failed
    /// and the errors tab should open with the cause.
    func push() async -> Bool {
        guard let worktree = listedWorktree else {
            return true
        }

        isBranchActionRunning = true
        defer { isBranchActionRunning = false }
        do {
            let destination = try await performPush(worktree)
            pullRequests.invalidateListings(repositoryPath: repository.path)
            isPushed = true
            setStatus("Pushed.", detail: Self.describe(push: destination, branch: worktree.branch))
            Self.requestSidebarRefresh()
            await reload(keepingSelection: true)
            refreshAfterPush()
            return true
        } catch {
            report(error.localizedDescription)
            return false
        }
    }

    /// Rebases onto origin with signed commits; false means the
    /// rebase aborted and the errors tab should open with the cause.
    /// Merges a stacked pull request together with every one below
    /// it, in order; false opens the errors surface. GitHub decides
    /// how each is merged, so the button says only that it merges.
    func mergeStack() async -> Bool {
        guard let worktree = listedWorktree, let number = selected?.number else {
            return false
        }

        do {
            // Linked first, and only then merged: a chain of pull
            // requests GitHub does not hold as a stack must not be
            // merged as one, and linking is idempotent, so this
            // covers a bottom pull request opened anywhere else.
            // A link that fails takes the merge with it.
            try await performLinkStack(worktree)
            try await performMergeStack(worktree, number)
            pullRequests.invalidateListings(repositoryPath: repository.path)
            setStatus("Merging the stack.")
            await reload(keepingSelection: true)
            return true
        } catch {
            report(error.localizedDescription)
            return false
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

        let merges = selected.hasAutomerge == false && Self.isReadyToMerge(selected)
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
            report(error.localizedDescription)
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
