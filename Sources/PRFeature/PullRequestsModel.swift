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
        self.service = service
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
        fetchRemediationContext = { number in
            await github.remediationContext(repositoryPath: repository.path, number: number)
        }
    }

    deinit {
        // Tasks are owned by the view's lifetime.
    }

    // MARK: Internal

    let repository: Repository
    let branch: String?

    /// The conversation pane fetches its own details and caches.
    let github: GitHubClient
    let store: MetadataStore

    /// The repository's worktree items, refreshed by the view as the
    /// dashboard polls, so push and rebase states stay current.
    var items: [WorktreeItem]

    /// Which pull requests the tab lists.
    var scope: PullRequestScope = .worktree

    /// The selected conversation; the view writes nil to go back.
    var selected: PullRequestSummary?

    private(set) var summaries: [PullRequestSummary] = []
    private(set) var isLoading = false
    private(set) var fetchedLimit = 0
    private(set) var hasMergeQueue = false
    private(set) var status: String?

    /// Test seams: the live client by default, fakes in tests.
    var fetchList: (GitHubClient.ListScope, Int) async throws -> [PullRequestSummary]
    var fetchSummary: (Int) async throws -> PullRequestSummary?
    var fetchHasMergeQueue: () async -> Bool
    var fetchRemediationContext: (Int) async -> String

    /// The visible page; visiting the lookahead page refetches with
    /// a higher limit.
    var page = 0 {
        didSet {
            guard summaries.count == fetchedLimit,
                  (page + 1) * PullRequestListView.pageSize >= summaries.count
            else {
                return
            }

            Task { await reload(extending: true) }
        }
    }

    /// The scope's identity, part of the reload task identity.
    var scopeIdentity: String {
        String(describing: scope)
    }

    /// Whether the last fetch filled its limit, so more pages may
    /// exist beyond what is loaded.
    var hasMore: Bool {
        summaries.isEmpty == false && summaries.count == fetchedLimit
    }

    var branchItem: WorktreeItem? {
        items.first { $0.worktree.branch == branch }
    }

    /// Push makes sense with unpushed commits; nil upstream means
    /// nothing was ever pushed.
    var canPush: Bool {
        guard let item = branchItem else {
            return false
        }

        return (item.aheadOfUpstream ?? 1) > 0
    }

    /// Opening a pull request makes sense until one is open; it
    /// pushes first when needed.
    var canOpenPullRequest: Bool {
        branchItem != nil
            && summaries.contains { $0.headBranch == branch && $0.state == "OPEN" } == false
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
            let fetched = try await fetchList(scope.listScope(branch: branch), limit)
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

    func worktree(for summary: PullRequestSummary) -> Worktree? {
        items.first { $0.worktree.branch == summary.headBranch }?.worktree
    }

    func ship() async {
        guard let item = branchItem else {
            return
        }

        do {
            status = try await service.pushAndCreatePullRequest(worktree: item.worktree)
            await reload(keepingSelection: true)
        } catch {
            ErrorLog.shared.report(error.localizedDescription)
        }
    }

    func push() async {
        guard let item = branchItem else {
            return
        }

        do {
            try await service.push(worktree: item.worktree)
            status = "Pushed."
            await reload(keepingSelection: true)
        } catch {
            ErrorLog.shared.report(error.localizedDescription)
        }
    }

    /// Rebases onto origin with signed commits; false means the
    /// rebase aborted and the errors tab should open with the cause.
    func rebaseSigned() async -> Bool {
        guard let item = branchItem else {
            return true
        }

        do {
            try await service.rebaseSigned(worktree: item.worktree)
            status = "Rebased onto origin."
            await reload(keepingSelection: true)
            return true
        } catch {
            ErrorLog.shared.report(error.localizedDescription)
            return false
        }
    }

    func remediate(_ summary: PullRequestSummary) async throws {
        guard let worktree = worktree(for: summary) else {
            return
        }

        let context = await fetchRemediationContext(summary.number)
        let prompt = """
        Address the following review comments and failing checks on pull request #\(summary.number), \
        then commit your fixes. Do not push.

        \(context)
        """
        _ = try await service.launchAgent(in: worktree, prompt: prompt, agent: .claudeCode)
        status = "Fix agent launched for #\(summary.number)."
    }

    func act(_ work: @escaping () async throws -> Void) {
        Task {
            do {
                try await work()
                status = "Done."
                await reload(keepingSelection: true)
            } catch {
                ErrorLog.shared.report(error.localizedDescription)
            }
        }
    }

    // MARK: Private

    /// Fetches stay one page ahead of the visible one, so the pager
    /// knows whether a next page exists.
    private static let pageLookahead = 2

    private let service: SessionService

    private var cacheKey: String {
        repository.path + "#" + scopeIdentity + "#" + (branch ?? "")
    }
}
