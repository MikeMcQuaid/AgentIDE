import AgentIDEData
import AgentIDEDomain
import Foundation
import Observation
import TerminalUI
import UserNotifications

// MARK: - DashboardModel

/// The dashboard's state: repositories, worktrees, sessions and
/// archives, refreshed by polling and notifying on completion.
@preconcurrency
@Observable
@MainActor
public final class DashboardModel {
    // MARK: Lifecycle

    /// Creates the model, seeding the sidebar from the last run's
    /// snapshot so launch paints instantly.
    public init(service: SessionService, store: MetadataStore, github: GitHubClient) {
        self.service = service
        self.store = store
        self.github = github
        groups = store.load().cachedSidebar.map { cached in
            let repository = Repository(name: cached.name, path: cached.path, fullName: cached.fullName)
            let items = cached.worktrees.map { worktree in
                WorktreeItem(
                    worktree: Worktree(
                        repositoryName: cached.name,
                        repositoryPath: cached.path,
                        branch: worktree.branch,
                        path: worktree.path,
                    ),
                    session: nil,
                    isDirty: false,
                    aheadOfUpstream: nil,
                    hasUnread: false,
                )
            }
            return RepositoryGroup(repository: repository, items: items)
        }
    }

    deinit {
        // The polling task is cancelled by its owning view.
    }

    // MARK: Public

    /// The grouped worktrees per repository.
    public private(set) var groups: [RepositoryGroup] = []

    /// Sessions not created by AgentIDE.
    public private(set) var foreign: [AgentSession] = []

    /// Whether the tmux session manager sheet is shown.
    public var showsSessionManager = false

    /// The repository the sheet preselects, set by the toolbar's new
    /// session button.
    public var newSessionRepository: Repository?

    /// The last background error, for display; the repository
    /// extension also reports through it.
    public internal(set) var status: String?

    /// A failure shown inline on the middle-pane screens: the finder
    /// and new-session pages render before the split view exists, so
    /// the Errors tab is not visible from them.
    public internal(set) var screenError: String?

    /// Whether the new session page is shown; the middle-pane pages
    /// are mutually exclusive, so showing one cancels the other.
    public var showsNewSession = false {
        didSet {
            if showsNewSession {
                showsRepositoryFinder = false
            }
        }
    }

    /// Whether the repository finder page is shown.
    public var showsRepositoryFinder = false {
        didSet {
            if showsRepositoryFinder {
                showsNewSession = false
            }
        }
    }

    /// The selected worktree item. Selecting an item marks it seen,
    /// clearing its unread dot immediately and any manual mark, and
    /// persists so the next launch resumes on the same worktree.
    public var selection: WorktreeItem? {
        didSet {
            guard let selection, selection.id != oldValue?.id else {
                return
            }

            UserDefaults.standard.set(selection.worktree.path, forKey: Self.selectedWorktreeKey)
            service.markSeen(worktreePath: selection.worktree.path)
            clearUnread(at: selection.worktree.path)
            // The freshly selected branch jumps the polling queue.
            nextPullRequestFetch[selection.worktree.repositoryPath + "#" + selection.worktree.branch] = nil
        }
    }

    /// The repositories available for new sessions.
    public var repositories: [Repository] {
        service.repositories()
    }

    /// Reports an action's failure into the app-wide error log, for
    /// actions views run against services directly.
    public func report(_ message: String) {
        ErrorLog.shared.report(message)
    }

    /// Selecting from the sidebar is a middle-pane action, so it
    /// cancels any form the middle pane is showing.
    public func select(_ item: WorktreeItem) {
        showsNewSession = false
        showsRepositoryFinder = false
        selection = item
    }

    /// Reloads everything and notifies about newly finished or
    /// newly unread sessions. The selected worktree is on screen, so
    /// its activity counts as seen; a manual unread mark survives.
    public func refresh() async {
        if let selection {
            service.acknowledgeActivity(worktreePath: selection.worktree.path)
        }
        let overview = await service.overview()
        notifyChanges(from: groups, to: overview.groups)
        groups = overview.groups
        foreign = overview.foreign
        if let selected = selection {
            selection = overview.groups.flatMap(\.items).first { $0.id == selected.id }
        } else if hasRestoredSelection == false {
            let stored = UserDefaults.standard.string(forKey: Self.selectedWorktreeKey)
            selection = overview.groups.flatMap(\.items).first { $0.worktree.path == stored }
        }
        hasRestoredSelection = true
        cacheSidebar(overview.groups)
        await refreshStalePullRequests()
    }

    /// Polls the system on an interval while the dashboard is alive.
    /// Model discovery runs once per launch, so the pickers track the
    /// installed CLIs.
    public func poll() async {
        // The sidebar and the restored selection come first: model
        // discovery and the notification prompt take seconds, and
        // the window showed "no worktree selected" while they ran.
        await refresh()
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        for agent in AgentKind.allCases {
            if let models = await service.discoverModels(for: agent) {
                discoveredModels[agent] = models
            }
        }
        while Task.isCancelled == false {
            await refresh()
            try? await Task.sleep(for: .seconds(Self.pollInterval))
        }
    }

    /// The models and efforts an agent offers: models the CLI
    /// reported at startup when it answered, the curated fallback
    /// otherwise.
    public func launchChoices(for agent: AgentKind) -> (models: [String], efforts: [String]) {
        let fallback = service.launchChoices(for: agent)
        return (discoveredModels[agent] ?? fallback.models, fallback.efforts)
    }

    /// Deletes a worktree; its conversations stay readable in the
    /// repository's sessions browser.
    public func delete(item: WorktreeItem) async {
        do {
            try await service.deleteWorktree(item: item)
            if selection?.id == item.id {
                selection = nil
            }
            await refresh()
        } catch {
            ErrorLog.shared.report(error.localizedDescription)
        }
    }

    /// Flags the item unread until it is next viewed.
    public func markUnread(item: WorktreeItem) async {
        service.markUnread(worktreePath: item.worktree.path)
        await refresh()
    }

    /// The repository's open issues, cached for instant pickers; an
    /// empty answer falls back to the cache.
    public func openIssues(repository: Repository) async -> [IssueSummary] {
        let fresh = await service.openIssues(repository: repository)
        guard fresh.isEmpty == false else {
            return store.load().openIssuesCache[repository.path] ?? []
        }

        var metadata = store.load()
        metadata.openIssuesCache[repository.path] = fresh
        store.save(metadata)
        return fresh
    }

    /// The repository's open pull requests, cached like the issues.
    public func openPullRequests(repository: Repository) async -> [PullRequestSummary] {
        let fresh = await (try? service.openPullRequests(repository: repository)) ?? []
        guard fresh.isEmpty == false else {
            return store.load().openPullRequestsCache[repository.path] ?? []
        }

        var metadata = store.load()
        metadata.openPullRequestsCache[repository.path] = fresh
        store.save(metadata)
        return fresh
    }

    /// Fetches the item's repository and refreshes.
    public func fetch(item: WorktreeItem) async {
        do {
            let repository = Repository(
                name: item.worktree.repositoryName,
                path: item.worktree.repositoryPath,
            )
            try await service.fetch(repository: repository)
            status = "Fetched \(repository.name)."
            await refresh()
        } catch {
            ErrorLog.shared.report(error.localizedDescription)
        }
    }

    /// Fetches origin and hard-resets the main checkout to its
    /// default branch, then refreshes.
    public func fetchAndReset(item: WorktreeItem) async {
        do {
            let repository = Repository(
                name: item.worktree.repositoryName,
                path: item.worktree.repositoryPath,
            )
            try await service.fetchAndReset(repository: repository)
            status = "Reset \(repository.name) to origin."
            await refresh()
        } catch {
            ErrorLog.shared.report(error.localizedDescription)
        }
    }

    // MARK: Internal

    /// Internal rather than private so the repository extension file
    /// can reach the service too.
    let service: SessionService

    /// Internal so the pull request extension file can query GitHub.
    let github: GitHubClient

    /// Each worktree branch's open pull request, keyed by repository
    /// path and branch. A cached nil records "asked, none open", so
    /// failures keep the last good answer either way. Stored here,
    /// managed by the pull request extension file.
    var branchPullRequests: [String: PullRequestSummary?] = [:]

    /// When each branch's pull request is next due, by cache key.
    var nextPullRequestFetch: [String: Date] = [:]

    /// Internal so the pull request extension file can persist its
    /// cache.
    let store: MetadataStore

    // MARK: Private

    private static let pollInterval = 5
    private static let selectedWorktreeKey = "selectedWorktreePath"

    /// Models each CLI reported at startup; absent agents fall back.
    private var discoveredModels: [AgentKind: [String]] = [:]

    /// Whether the persisted selection has been re-applied, tried on
    /// the first refresh only so a deliberate deselection sticks.
    private var hasRestoredSelection = false

    private func clearUnread(at path: String) {
        for groupIndex in groups.indices {
            let items = groups[groupIndex].items
            for itemIndex in items.indices where items[itemIndex].worktree.path == path {
                groups[groupIndex].items[itemIndex].hasUnread = false
            }
        }
    }

    private func cacheSidebar(_ groups: [RepositoryGroup]) {
        var metadata = store.load()
        metadata.cachedSidebar = groups.map { group in
            var cached = CachedRepository()
            cached.name = group.repository.name
            cached.fullName = group.repository.fullName
            cached.path = group.repository.path
            cached.worktrees = group.items.map { item in
                var worktree = CachedWorktree()
                worktree.branch = item.worktree.branch
                worktree.path = item.worktree.path
                return worktree
            }
            return cached
        }
        store.save(metadata)
    }
}
