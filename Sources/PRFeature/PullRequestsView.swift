import AgentIDEData
import AgentIDEDomain
import SwiftUI
import TerminalUI

/// The repository's pull requests: a paginated title list clicking
/// through to each pull request's conversation and actions.
public struct PullRequestsView: View {
    // MARK: Lifecycle

    /// Creates the pull request list for a repository, filtered to
    /// one branch when given; the store caches listings and
    /// conversations between sessions.
    public init(
        repository: Repository,
        items: [WorktreeItem],
        github: GitHubClient,
        service: SessionService,
        store: MetadataStore,
        branch: String? = nil,
    ) {
        self.repository = repository
        self.items = items
        self.github = github
        self.service = service
        self.store = store
        self.branch = branch
    }

    // MARK: Public

    /// The scope picker over the list or the selected conversation.
    public var body: some View {
        VStack(spacing: 0) {
            scopePicker
            Divider()
            if let selected {
                conversation(for: selected)
            } else {
                listView
            }
        }
        .safeAreaInset(edge: .bottom) { footer }
        // The branch joins the identity so switching worktrees in
        // the same repository reloads the list.
        .task(id: repository.id + scopeIdentity + (branch ?? "")) { await reload() }
        .task(id: repository.id) {
            hasMergeQueue = await github.hasMergeQueue(repositoryPath: repository.path)
        }
    }

    // MARK: Private

    private enum Scope: Hashable {
        case worktree
        case mine
        case open
    }

    private static let footerPadding: CGFloat = 8
    /// Fetches stay one page ahead of the visible one, so the pager
    /// knows whether a next page exists.
    private static let pageLookahead = 2

    /// The errors tab's position in the utility tab order, driven
    /// through the storage signal bus.
    private static let errorsTabIndex = 5

    /// The cross-module signal that switches the utility pane's tab.
    @AppStorage("utilityTabIndex")
    private var utilityTabIndex = 0

    @State private var scope: Scope = .worktree
    @State private var summaries: [PullRequestSummary] = []
    @State private var selected: PullRequestSummary?
    @State private var isLoading = false
    @State private var page = 0
    @State private var fetchedLimit = 0
    @State private var hasMergeQueue = false
    @State private var status: String?

    private let repository: Repository
    private let items: [WorktreeItem]
    private let github: GitHubClient
    private let service: SessionService
    private let store: MetadataStore
    private let branch: String?

    private var cacheKey: String {
        repository.path + "#" + scopeIdentity + "#" + (branch ?? "")
    }

    private var scopeIdentity: String {
        String(describing: scope)
    }

    private var listScope: GitHubClient.ListScope {
        switch scope {
        case .worktree:
            .branch(branch ?? "")

        case .mine:
            .mine

        case .open:
            .open
        }
    }

    /// Push makes sense with unpushed commits or without an open
    /// pull request for this worktree's branch; nil upstream means
    /// nothing was ever pushed.
    private var canShip: Bool {
        guard let item = items.first(where: { $0.worktree.branch == branch }) else {
            return false
        }

        let hasOpen = summaries.contains { $0.headBranch == branch && $0.state == "OPEN" }
        return (item.aheadOfUpstream ?? 1) > 0 || hasOpen == false
    }

    private var scopePicker: some View {
        Picker("Scope", selection: $scope) {
            Text("Worktree").tag(Scope.worktree)
            Text("Mine").tag(Scope.mine)
            Text("Open").tag(Scope.open)
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .labelsHidden()
        .padding(Self.footerPadding)
        .hoverHelp(
            "Worktree: this branch's pull requests, open and closed. Mine: open ones you created. Open: every open one",
        )
    }

    private var listView: some View {
        PullRequestListView(
            summaries: summaries,
            isLoading: isLoading,
            hasMore: summaries.isEmpty == false && summaries.count == fetchedLimit,
            stackDepth: { stackDepth(for: $0) },
            onSelect: { select($0) },
            page: $page,
        )
        // Visiting a page beyond the fetched data refetches with a
        // higher limit; a short answer means there is no more.
        .onChange(of: page) {
            guard summaries.count == fetchedLimit,
                  (page + 1) * PullRequestListView.pageSize >= summaries.count
            else {
                return
            }

            Task { await reload(extending: true) }
        }
    }

    private var footer: some View {
        PullRequestFooterView(
            canShip: canShip,
            canRebase: items.contains { $0.worktree.branch == branch },
            status: status,
            onShip: { Task { await ship() } },
            onRebase: { Task { await rebaseSigned() } },
            onRefresh: { Task { await reload(keepingSelection: true) } },
        )
    }

    private func conversation(for summary: PullRequestSummary) -> some View {
        PullRequestConversationPane(
            summary: summary,
            canRemediate: worktree(for: summary) != nil,
            stackDepth: stackDepth(for: summary),
            hasMergeQueue: hasMergeQueue,
            github: github,
            repositoryPath: repository.path,
            store: store,
            onBack: { selected = nil },
            onAutomerge: {
                act { try await github.enableAutomerge(repositoryPath: repository.path, number: summary.number) }
            },
            onMerge: {
                act { try await github.merge(repositoryPath: repository.path, number: summary.number) }
            },
            onRemediate: { act { try await remediate(summary) } },
        )
    }

    private func ship() async {
        guard let item = items.first(where: { $0.worktree.branch == branch }) else {
            return
        }

        do {
            status = try await service.pushAndCreatePullRequest(worktree: item.worktree)
            await reload(keepingSelection: true)
        } catch {
            ErrorLog.shared.report(error.localizedDescription)
        }
    }

    /// Rebases onto origin with signed commits; a failure aborted
    /// the rebase already, so the errors tab opens with the cause.
    private func rebaseSigned() async {
        guard let item = items.first(where: { $0.worktree.branch == branch }) else {
            return
        }

        do {
            try await service.rebaseSigned(worktree: item.worktree)
            status = "Rebased onto origin."
            await reload(keepingSelection: true)
        } catch {
            ErrorLog.shared.report(error.localizedDescription)
            utilityTabIndex = Self.errorsTabIndex
        }
    }

    private func worktree(for summary: PullRequestSummary) -> Worktree? {
        items.first { $0.worktree.branch == summary.headBranch }?.worktree
    }

    /// Opens a conversation and refreshes its header: the open
    /// scope's light rows gain their status icons here.
    private func select(_ summary: PullRequestSummary) {
        selected = summary
        Task {
            let full = try? await github.pullRequestSummary(
                repositoryPath: repository.path,
                number: summary.number,
            )
            if let full, selected?.number == full.number {
                selected = full
            }
        }
    }

    /// The stack size, following base branches that are other listed
    /// pull requests' heads.
    private func stackDepth(for summary: PullRequestSummary) -> Int {
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

    /// The cached listing paints instantly while the fetch runs; a
    /// kept selection is re-selected once the fetch answers, and a
    /// single result opens its conversation directly. Extending
    /// keeps the current page and raises the fetch limit.
    private func reload(keepingSelection: Bool = false, extending: Bool = false) async {
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
            let fetched = try await github.pullRequests(
                repositoryPath: repository.path,
                scope: listScope,
                limit: limit,
            )
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

    private func remediate(_ summary: PullRequestSummary) async throws {
        guard let worktree = worktree(for: summary) else {
            return
        }

        let context = await github.remediationContext(repositoryPath: repository.path, number: summary.number)
        let prompt = """
        Address the following review comments and failing checks on pull request #\(summary.number), \
        then commit your fixes. Do not push.

        \(context)
        """
        _ = try await service.launchAgent(in: worktree, prompt: prompt, agent: .claudeCode)
        status = "Fix agent launched for #\(summary.number)."
    }

    private func act(_ work: @escaping () async throws -> Void) {
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
}
