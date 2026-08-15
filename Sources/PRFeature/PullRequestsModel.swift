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
            await github.reviewThreads(repositoryPath: repository.path, number: number)
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

    private(set) var summaries: [PullRequestSummary] = []
    private(set) var isLoading = false
    private(set) var fetchedLimit = 0
    private(set) var hasMergeQueue = false

    /// The footer's status line. Written only by the actions
    /// extension.
    var status: String?

    /// The pull request creation form's fields; the template loads
    /// from the repository on reload when the form shows.
    var prTitle = ""
    var prBody = ""
    var prTemplate = ""

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
    var fetchCurrentBranch: (String) async -> String?
    var fetchRebaseNeed: (Worktree) async -> SessionService.RebaseNeed
    var performPush: (Worktree) async throws -> Void
    var performRebase: (Worktree) async throws -> Void
    var checkTipSigned: (String) async -> Bool

    /// Whether the list pane shows the creation form instead: the
    /// worktree scope with no open pull request for the branch.
    var needsCreateForm: Bool {
        scope == .worktree && branchItem != nil && isLoading == false
            && summaries.contains { $0.headBranch == listedBranch && $0.state == "OPEN" } == false
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

    /// Whether the last fetch filled its limit, so more pages may
    /// exist beyond what is loaded.
    var hasMore: Bool {
        summaries.isEmpty == false && summaries.count == fetchedLimit
    }

    var branchItem: WorktreeItem? {
        items.first { $0.worktree.branch == branch }
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
            if prTemplate.isEmpty {
                prTemplate = template ?? ""
            }
            // A one-commit branch is its own description: the form
            // defaults to that commit, no model involved.
            if prTitle.isEmpty, prBody.isEmpty {
                let commits = await fetchCommitMessages(worktree)
                if commits.count == 1, let only = commits.first {
                    apply(description: Self.description(splitFromMessage: only))
                }
            }
            if let live = await fetchCurrentBranch(worktree.path) {
                currentBranch = live
            }
        }
        if extending == false {
            page = 0
            selected = nil
            summaries = store.load().pullRequestListsCache[cacheKey]?.summaries ?? []
        }
        defer { isLoading = false }
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
        } catch {
            ErrorLog.shared.report(error.localizedDescription)
        }
    }

    /// Refreshes one pull request's header wherever it shows, so
    /// actions like resolving conversations reflect immediately in
    /// the selected conversation and its listed row.
    func refreshSummary(_ number: Int) async {
        guard let full = try? await fetchSummary(number) else {
            return
        }

        if selected?.number == number {
            selected = full
        }
        if let index = summaries.firstIndex(where: { $0.number == number }) {
            summaries[index] = full
        }
    }

    /// Opens a conversation and refreshes its header: the open
    /// scope's light rows gain their status icons here.
    func select(_ summary: PullRequestSummary) {
        selected = summary
        Task {
            let full = try? await fetchSummary(summary.number)
            if let full, selected?.number == full.number {
                selected = full
            }
        }
    }

    // MARK: Private

    /// Fetches stay one page ahead of the visible one, so the pager
    /// knows whether a next page exists.
    private static let pageLookahead = 2

    private var cacheKey: String {
        repository.path + "#" + String(describing: scope) + "#" + (listedBranch ?? "")
    }
}
