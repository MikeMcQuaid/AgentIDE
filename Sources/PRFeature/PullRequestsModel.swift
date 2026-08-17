import AgentIDEData
import AgentIDEDomain
import Observation
import TerminalUI

/// The pull request tab's state and actions: listing, pagination,
/// selection enrichment, caching and the branch actions, kept out of
/// the view so the logic tests without a window. The fetchers are
/// stored closures, so tests replace GitHub with fakes.
@preconcurrency
@Observable
@MainActor
final class PullRequestsModel {
    // MARK: Lifecycle

    // The init is one flat seam-wiring list; splitting it would
    // scatter the wiring without shortening anything real.
    // swiftlint:disable function_body_length
    /// Creates the model for one repository and optional branch.
    init(
        repository: Repository,
        branch: String?,
        items: [WorktreeItem],
        github: GitHubClient,
        service: SessionService,
        store: MetadataStore,
    ) {
        self.repository = repository
        self.branch = branch
        self.items = items
        self.github = github
        self.store = store
        fetchList = { scope, limit in
            try await github.pullRequests(repositoryPath: repository.path, scope: scope, limit: limit)
        }
        fetchSummary = { number in
            try await github.pullRequestSummary(repositoryPath: repository.path, number: number)
        }
        fetchHasMergeQueue = {
            await github.hasMergeQueue(repositoryPath: repository.path)
        }
        fetchThreads = { number in
            let answer = await github.conversationThreads(repositoryPath: repository.path, number: number)
            if let failure = answer.graphQLFailure {
                ErrorLog.shared.report("Conversations fell back to REST (no resolve buttons): " + failure)
            }
            return answer.threads
        }
        fetchFailingChecks = { number in
            await github.failingChecks(repositoryPath: repository.path, number: number)
        }
        performCreate = { worktree, title, body in
            try await github.createPullRequest(worktreePath: worktree.path, title: title, body: body)
        }
        fetchTemplate = { path in
            GitHubClient.pullRequestTemplate(in: path)
        }
        fetchCommitMessages = { worktree in
            await service.commitMessages(worktree: worktree)
        }
        generateDescription = { commits in
            await service.draftPullRequestDescription(fromCommits: commits)
        }
        fillTemplate = { commits, template in
            await service.fillPullRequestTemplate(fromCommits: commits, template: template)
        }
        performMergeChange = { summary in
            if summary.hasAutomerge {
                try await github.disableAutomerge(repositoryPath: repository.path, number: summary.number)
            } else if summary.checks == "SUCCESS", summary.mergeable == "MERGEABLE" {
                try await github.merge(repositoryPath: repository.path, number: summary.number)
            } else {
                try await github.enableAutomerge(repositoryPath: repository.path, number: summary.number)
            }
        }
        performPostMergeCleanup = { worktree, mergedBranch in
            let report = await service.cleanUpAfterMerge(worktree: worktree, mergedBranch: mergedBranch)
            for note in report.notes {
                ErrorLog.shared.note(note)
            }
            for failure in report.failures {
                ErrorLog.shared.report(failure)
            }
            // The cleanup changed the checked-out branch and deleted
            // others, so the sidebar's rows are stale the moment it
            // finishes; waiting for the next poll showed a branch
            // that no longer exists.
            Self.requestSidebarRefresh()
        }
        fetchCurrentBranch = { path in
            await service.currentBranch(worktreePath: path)
        }
        fetchRebaseNeed = { worktree in
            await service.rebaseNeed(worktree: worktree)
        }
        performPush = { worktree in
            try await service.push(worktree: worktree)
        }
        performRebase = { worktree in
            try await service.rebaseSigned(worktree: worktree)
        }
        checkTipSigned = { path in
            await service.isTipSigned(worktreePath: path)
        }
        currentBranch = branch
    }

    // swiftlint:enable function_body_length

    deinit {
        // Tasks are owned by the view's lifetime.
    }

    // MARK: Internal

    let repository: Repository
    let branch: String?

    /// The conversation pane fetches its own details and caches.
    let github: GitHubClient
    let store: MetadataStore

    /// The branch actually checked out in the worktree, refreshed on
    /// reload; agents sometimes switch branches inside a worktree.
    private(set) var currentBranch: String?

    /// True after an in-app push succeeds, dimming Push until the
    /// next item refresh proves new commits. Written only by the
    /// actions extension.
    var isPushed = false

    /// What a signed rebase would change right now, refreshed on
    /// reload; the button dims and names its work from this.
    private(set) var rebaseNeed: SessionService.RebaseNeed = .nothing

    /// Whether the tip commit is GPG signed, refreshed on reload;
    /// pushing unsigned commits is never allowed, so Push dims until
    /// Rebase on origin signs the branch.
    private(set) var isTipSigned = true

    /// Which pull requests the tab lists.
    var scope: PullRequestScope = .worktree

    /// The selected conversation; the view writes nil to go back.
    var selected: PullRequestSummary?

    var summaries: [PullRequestSummary] = []
    private(set) var isLoading = false

    /// True once the first listing answered; the creation form only
    /// appears after that, and mid-reload churn never hides it.
    var hasLoaded = false
    private(set) var fetchedLimit = 0
    private(set) var hasMergeQueue = false

    /// The footer's status line. Written only by the actions
    /// extension.
    var status: String?

    /// The template as the repository wrote it, so Open PR can wait
    /// for it to be filled in rather than opened with placeholders.
    var originalTemplate = ""

    /// Suppresses saving while a draft is restored, so restoring
    /// never writes back what it just read.
    var loadingDraft = false

    /// Whether the repository has a pull request template; without
    /// one the form shows no template field at all.
    private(set) var hasTemplate = false

    /// Test seams: the live client and service by default, fakes in
    /// tests.
    var fetchList: (GitHubClient.ListScope, Int) async throws -> [PullRequestSummary]
    var fetchSummary: (Int) async throws -> PullRequestSummary?
    var fetchHasMergeQueue: () async -> Bool
    var fetchThreads: (Int) async -> [ReviewThread]
    var fetchFailingChecks: (Int) async -> String
    var performCreate: (Worktree, String, String) async throws -> String
    var fetchTemplate: (String) -> String?
    var fetchCommitMessages: (Worktree) async -> [String]
    var generateDescription: ([String]) async -> (title: String, body: String)?
    var fillTemplate: ([String], String) async -> String?
    var performMergeChange: (PullRequestSummary) async throws -> Void
    var performPostMergeCleanup: (Worktree, String) async -> Void
    var fetchCurrentBranch: (String) async -> String?
    var fetchRebaseNeed: (Worktree) async -> SessionService.RebaseNeed
    var performPush: (Worktree) async throws -> Void
    var performRebase: (Worktree) async throws -> Void
    var checkTipSigned: (String) async -> Bool

    /// The pull request creation form's fields; the template loads
    /// from the repository on reload when the form shows.
    var prTitle = "" {
        didSet { saveDraft() }
    }

    var prBody = "" {
        didSet { saveDraft() }
    }

    var prTemplate = "" {
        didSet { saveDraft() }
    }

    /// The repository's worktree items, refreshed by the view as the
    /// dashboard polls; fresh counts also clear the local pushed
    /// mark, so new commits light Push up again.
    var items: [WorktreeItem] {
        didSet {
            isPushed = false
        }
    }

    /// The visible page; visiting the lookahead page refetches with
    /// a higher limit. The guards keep `reload`'s own `page = 0`
    /// reset and a fresh model (both counts zero) from spawning a
    /// second concurrent reload.
    var page = 0 {
        didSet {
            guard page != oldValue,
                  fetchedLimit > 0,
                  summaries.count == fetchedLimit,
                  (page + 1) * PullRequestListView.pageSize >= summaries.count
            else {
                return
            }

            Task { await reload(extending: true) }
        }
    }

    /// Push makes sense with unpushed commits that this tab has not
    /// already pushed and a GPG-signed tip; nil upstream means
    /// nothing was ever pushed.
    var canPush: Bool {
        guard let item = branchItem, isPushed == false, isTipSigned else {
            return false
        }

        return (item.aheadOfUpstream ?? 1) > 0
    }

    /// Why Push is in its current state, for the button's hover:
    /// with nothing to push that is the whole story, and signing
    /// only matters once commits are waiting.
    var pushHelp: String {
        guard let item = branchItem, isPushed == false, (item.aheadOfUpstream ?? 1) > 0 else {
            return "Everything is already pushed"
        }
        guard isTipSigned else {
            return "The tip commit is not GPG signed; Rebase on origin signs the branch first"
        }

        return "Push this branch's unpushed commits to origin; a failure reports to the Errors tab"
    }

    /// The rebase button's label names exactly what it would do.
    var rebaseTitle: String {
        switch rebaseNeed {
        case .sign:
            "Sign commits"

        case .rebaseAndSign:
            "Rebase and sign"

        case .nothing,
             .rebase:
            "Rebase on origin"
        }
    }

    /// Rebase only lights up when it would actually change
    /// something: move the base, sign commits, or both.
    var canRebase: Bool {
        branchItem != nil && rebaseNeed != SessionService.RebaseNeed.nothing
    }

    /// The branch the tab lists and compares against: the checked
    /// out one when known, the worktree's recorded one otherwise.
    var listedBranch: String? {
        currentBranch ?? branch
    }

    var cacheKey: String {
        repository.path + "#" + String(describing: scope) + "#" + (listedBranch ?? "")
    }

    /// Where a branch's draft is stored, nil without a branch.
    func loadMergeQueue() async {
        hasMergeQueue = await fetchHasMergeQueue()
    }

    /// The cached listing paints instantly while the fetch runs; a
    /// kept selection is re-selected once the fetch answers, and a
    /// single result opens its conversation directly. Extending
    /// keeps the current page and raises the fetch limit.
    func reload(keepingSelection: Bool = false, extending: Bool = false) async {
        let previous = keepingSelection ? selected?.number : nil
        isLoading = true
        if let worktree = branchItem?.worktree {
            isTipSigned = await checkTipSigned(worktree.path)
            rebaseNeed = await fetchRebaseNeed(worktree)
            let template = fetchTemplate(worktree.path)
            hasTemplate = template != nil
            loadDraft()
            originalTemplate = template ?? ""
            if prTemplate.isEmpty {
                prTemplate = originalTemplate
            }
            await prefillFromSingleCommit(worktree)
            if let live = await fetchCurrentBranch(worktree.path) {
                currentBranch = live
            }
        }
        if extending == false {
            page = 0
            selected = nil
            paintCachedListing()
        }
        defer {
            isLoading = false
            hasLoaded = true
        }
        // Captured before the await: a slow answer for an already
        // switched scope must neither show nor cache under the new
        // scope's key.
        let requested = cacheKey
        do {
            let limit = (page + Self.pageLookahead) * PullRequestListView.pageSize
            let fetched = try await fetchList(scope.listScope(branch: listedBranch), limit)
            guard Task.isCancelled == false, requested == cacheKey else {
                return
            }

            summaries = fetched
            fetchedLimit = limit
            var metadata = store.load()
            metadata.pullRequestListsCache[requested] = CachedPullRequestList(summaries: fetched)
            store.save(metadata)
            if extending == false {
                let chosen = fetched.first { $0.number == previous }
                    ?? (fetched.count == 1 ? fetched.first : nil)
                if let chosen {
                    select(chosen)
                }
            }
            ServiceStatus.shared.recordSuccess()
        } catch {
            ServiceStatus.shared.record(failure: error, doing: "Pull requests for " + repository.name)
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

    // MARK: Private

    /// Fetches stay one page ahead of the visible one, so the pager
    /// knows whether a next page exists.
    private static let pageLookahead = 2
}
