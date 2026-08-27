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
    public init(
        service: SessionService,
        store: MetadataStore,
        github: GitHubClient,
        launchProgress: LaunchProgress = LaunchProgress(),
    ) {
        self.service = service
        self.store = store
        self.github = github
        self.launchProgress = launchProgress
        restoreCachedSidebar()
        restoreDiscoveredModels()
    }

    deinit {
        // The polling task is cancelled by its owning view.
    }

    // MARK: Public

    /// The grouped worktrees per repository.
    /// Written by refresh and, for the placeholder row a new session
    /// shows while it is created, the sessions extension.
    public internal(set) var groups: [RepositoryGroup] = []

    /// Sessions not created by AgentIDE.
    public private(set) var foreign: [AgentSession] = []

    /// The step log the current launch narrates into, shown by the
    /// pane covering the split while a session is created or resumed.
    public let launchProgress: LaunchProgress

    /// Whether the session manager sheet is shown.
    public var showsSessionManager = false

    /// Whether the first reading of the system has landed; until then
    /// the window shows progress, not an empty selection.
    public internal(set) var hasLoaded = false

    /// Worktrees the last run left an agent running in, until the
    /// first herdr reading says otherwise: their panes wait for it
    /// rather than showing the conversations a closed session has.
    public internal(set) var awaitedSessions: Set<String> = []

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

    /// Worktrees mid-deletion, so their rows grey out instantly.
    public internal(set) var deletingPaths: Set<String> = []

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

            // A creation placeholder is selected for seconds only and
            // must not become the worktree the next launch restores.
            if selection.isPlaceholder == false {
                UserDefaults.standard.set(selection.worktree.path, forKey: Self.selectedWorktreeKey)
            }
            service.markSeen(worktreePath: selection.worktree.path)
            clearUnread(at: selection.worktree.path)
        }
    }

    /// The repositories available for new sessions.
    public var repositories: [Repository] {
        service.repositories()
    }

    /// Whether a worktree's pane should wait rather than decide.
    public func isAwaitingSession(_ item: WorktreeItem) -> Bool {
        awaitedSessions.contains(item.worktree.path)
    }

    /// Reports an action's failure into the app-wide error log, for
    /// actions views run against services directly.
    public func report(_ message: String) {
        ErrorLog.shared.report(message)
    }

    /// Opens the new session form for a repository (nil leaves the
    /// picker open) and points the sidebar at that repository's main
    /// checkout: the form is a middle-pane action on the repository,
    /// so the sidebar reflects it. Selection is set directly rather
    /// than through `select`, which would cancel the form it opens.
    public func openNewSession(for repository: Repository?) {
        newSessionRepository = repository
        showsNewSession = true
        selectMainCheckout(of: repository)
    }

    /// Points the sidebar at a repository's main checkout without
    /// touching whatever the middle pane shows; the picker in the
    /// new session form calls this as its choice changes.
    public func selectMainCheckout(of repository: Repository?) {
        guard let repository,
              let group = groups.first(where: { $0.repository.path == repository.path }),
              let main = group.items.first,
              selection?.id != main.id
        else {
            return
        }

        selection = main
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
    public func refresh(forcing repositoryPath: String? = nil) async {
        if let selection {
            service.acknowledgeActivity(worktreePath: selection.worktree.path)
        }
        // Reading the whole system takes a while, and the poll is
        // always doing it too. Without this the poll's older reading
        // could land after an action's newer one and put the state
        // it just changed back on screen: a cleaned-up branch would
        // reappear in the sidebar until the next tick.
        refreshGeneration += 1
        let generation = refreshGeneration
        let overview = await service.overview(scope: gitReadScope(forcing: repositoryPath), kept: groups)
        guard generation == refreshGeneration else {
            return
        }

        let listed = Self.retainingLostRows(of: groups, in: overview.groups)
        notifyChanges(from: groups, to: listed)
        groups = listed
        foreign = overview.foreign
        if let selected = selection {
            // A creation placeholder is never in a listing; it stays
            // selected until the creation replaces it.
            selection = listed.flatMap(\.items).first { $0.id == selected.id }
                ?? (selected.isPlaceholder ? selected : nil)
        } else if hasRestoredSelection == false {
            let stored = UserDefaults.standard.string(forKey: Self.selectedWorktreeKey)
            selection = listed.flatMap(\.items).first { $0.worktree.path == stored }
        }
        hasRestoredSelection = true
        hasLoaded = true
        // herdr has answered, so nothing is waiting on it any more.
        awaitedSessions = []
        cacheSidebar(listed)
        await refreshStacks(of: listed)
        await refreshStalePullRequests(forcing: repositoryPath)
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
        // Each CLI is asked its models beside the others, not one
        // after another, and the answers are kept: the pickers open
        // on the last list at once and take the fresh one when it
        // lands, where waiting on the sandbox took twenty seconds.
        await discoverModels()
        publishSessionChoices()
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
    /// repository's sessions browser. The path joins
    /// `deletingPaths` immediately, so the row can grey out the
    /// moment the click lands rather than when the deletion ends.
    public func delete(item: WorktreeItem) async {
        deletingPaths.insert(item.worktree.path)
        defer { deletingPaths.remove(item.worktree.path) }
        // Deselect immediately: the detail pane must not keep
        // showing, or allow re-entering, a worktree mid-deletion.
        if selection?.id == item.id {
            selection = nil
        }
        do {
            try await service.deleteWorktree(item: item)
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

        store.update { metadata in
            metadata.openIssuesCache[repository.path] = fresh
        }
        return fresh
    }

    /// The repository's open pull requests. The shared pull request
    /// store answers from what it knows unless a minute has passed,
    /// so the picker opens instantly without a cache of its own.
    public func openPullRequests(repository: Repository) async -> [PullRequestSummary] {
        await (try? service.openPullRequests(repository: repository)) ?? []
    }

    /// Fetches the item's repository and refreshes.
    public func fetch(item: WorktreeItem) async {
        do {
            let repository = Repository(
                name: item.worktree.repositoryName,
                path: item.worktree.repositoryPath,
            )
            try await service.fetch(repository: repository)
            ErrorLog.shared.note("Fetched \(repository.name).")
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
            ErrorLog.shared.note("Reset \(repository.name) to origin.")
            await refresh()
        } catch {
            ErrorLog.shared.report(error.localizedDescription)
        }
    }

    // MARK: Internal

    static let selectedWorktreeKey = "selectedWorktreePath"

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

    /// The stack git says each worktree holds, by worktree path, and
    /// when each is next worth deriving again. Managed by the stack
    /// extension file, which is where the rota lives.
    var derivedStacks: [String: BranchStack] = [:]

    var nextStackDerivation: [String: Date] = [:]

    /// The pull requests in each repository's merge queue, by
    /// repository path, as the shared store last answered. When it
    /// was asked is the store's business, like every other pull
    /// request timer.
    var queuedNumbers: [String: Set<Int>] = [:]

    /// Internal so the pull request extension file can persist its
    /// cache.
    let store: MetadataStore

    /// Whether the persisted selection has been re-applied, tried on
    /// the first refresh only so a deliberate deselection sticks.
    var hasRestoredSelection = false

    /// When each repository's git was last read in full; the git
    /// reads extension keeps it.
    var gitReadAt: [String: Date] = [:]

    /// Models each CLI reported, seeded from the last launch's answer
    /// by the cache extension; absent agents fall back.
    var discoveredModels: [AgentKind: [String]] = [:]

    /// Every pull request question the sidebar asks goes through
    /// here, which holds both the answers and when they arrived.
    var pullRequests: PullRequestStore {
        PullRequestStore(github: github, store: store)
    }

    // MARK: Private

    private static let pollInterval = 5

    /// Counts refreshes, so a slower one that started earlier can
    /// tell it has been superseded and drop its reading.
    private var refreshGeneration = 0

    private func clearUnread(at path: String) {
        for groupIndex in groups.indices {
            let items = groups[groupIndex].items
            for itemIndex in items.indices where items[itemIndex].worktree.path == path {
                groups[groupIndex].items[itemIndex].hasUnread = false
            }
        }
    }
}
