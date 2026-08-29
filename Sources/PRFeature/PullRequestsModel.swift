import AgentIDEData
import AgentIDEDomain
import Foundation
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
        worktreePath: String?,
        defaultBranch: String?,
        items: [WorktreeItem],
        github: GitHubClient,
        service: SessionService,
        store: MetadataStore,
    ) {
        self.repository = repository
        self.branch = branch
        self.worktreePath = worktreePath
        self.defaultBranch = defaultBranch
        self.items = items
        self.github = github
        self.store = store
        let gate = PullRequestStore(github: github, store: store)
        pullRequests = gate
        fetchList = { scope, limit in
            // The tab in front of you refreshes at the floor; a tab
            // kept mounted behind another worktree's asks GitHub far
            // less often, like the sidebar's rows.
            let isSelected = UserDefaults.standard.string(forKey: "selectedWorktreePath") == worktreePath
            return try await gate.listing(
                repositoryPath: repository.path,
                scope: scope,
                limit: limit,
                interval: isSelected ? PullRequestStore.minimumInterval : PullRequestStore.backgroundInterval,
            )
        }
        fetchSummary = { number in
            try await gate.summary(repositoryPath: repository.path, number: number)
        }
        fetchHasMergeQueue = {
            await gate.hasMergeQueue(repositoryPath: repository.path)
        }
        fetchThreads = { number in
            let answer = try? await gate.conversation(
                repositoryPath: repository.path,
                number: number,
                seededBody: nil,
            )
            if let failure = answer?.graphQLFailure {
                ErrorLog.shared.report("Conversations fell back to REST (no resolve buttons): " + failure)
            }
            return answer?.threads ?? []
        }
        performCreate = { worktree, title, body in
            try await service.createPullRequest(worktree: worktree, title: title, body: body)
        }
        performLinkStack = { worktree in
            try await service.linkStack(worktree: worktree)
        }
        performMergeStack = { worktree, number in
            try await service.mergeStack(worktree: worktree, number: number)
        }
        // On disk first, so an edited template is the one offered,
        // then out of git: a sparse checkout carries the tracked
        // template without materialising it, which is how the
        // Homebrew taps look.
        fetchTemplate = { path in
            if let onDisk = GitHubClient.pullRequestTemplate(in: path) {
                return onDisk
            }

            for candidate in GitHubClient.templatePaths {
                if let tracked = await service.trackedFile(worktreePath: path, path: candidate) {
                    return tracked
                }
            }
            return nil
        }
        fetchCommitMessages = { worktree, range in
            await service.commitMessages(worktree: worktree, range: range)
        }
        fetchCommitCount = { worktree, range in
            await service.commitCount(worktree: worktree, range: range)
        }
        launchChoices = { agent in
            let choices = service.launchChoices(for: agent)
            return (choices.models, service.defaultEffort(for: agent))
        }
        generateDescription = { commits in
            await service.draftPullRequestDescription(fromCommits: commits)
        }
        fillTemplate = { commits, template in
            await service.fillPullRequestTemplate(fromCommits: commits, template: template)
        }
        performMergeChange = { summary in
            defer { gate.invalidate(repositoryPath: repository.path, number: summary.number) }
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
        checkTipSigned = { worktree in
            // Settings can waive signing for repositories whose
            // remote runs no signature hook.
            AppSettings.requiresSignedCommits
                ? await service.isTipSigned(worktree: worktree)
                : true
        }
        currentBranch = branch
        wireStack(service: service)
        // Painted before anything is asked for, so a tab switched
        // away from and back to opens on the rows it had.
        paintCachedListing()
    }

    // swiftlint:enable function_body_length

    deinit {
        // Tasks are owned by the view's lifetime.
    }

    // MARK: Internal

    let repository: Repository
    let branch: String?

    /// The worktree the tab is for, whatever branch it holds now.
    let worktreePath: String?

    /// The conversation pane fetches its own details and caches.
    let github: GitHubClient

    /// Every pull request question the tab asks goes through here,
    /// which is also where the app keeps when it last asked.
    let pullRequests: PullRequestStore
    let store: MetadataStore

    /// The branch actually checked out in the worktree, refreshed on
    /// reload; agents sometimes switch branches inside a worktree.
    var currentBranch: String?

    /// True after an in-app push succeeds, dimming Push until the
    /// next item refresh proves new commits. Written only by the
    /// actions extension.
    var isPushed = false

    /// What a signed rebase would change right now, refreshed on
    /// reload; the button dims and names its work from this.
    /// Set only by the actions extension's fact refresh.
    var rebaseNeed: SessionService.RebaseNeed = .nothing

    /// The listed entry's own commits: what a push sends and what
    /// its pull request carries, counted from the branch's base.
    var commitsAboveBase = 0

    /// Whether the tip commit is GPG signed, refreshed on reload;
    /// pushing unsigned commits is never allowed, so Push dims until
    /// Rebase on origin signs the branch.
    var isTipSigned = true

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

    /// True while a pull request is being opened: the form keeps
    /// every word it holds and takes no more until GitHub answers.
    var isOpening = false

    /// Whether the repository has a pull request template; without
    /// one the form shows no template field at all.
    var hasTemplate = false

    /// Test seams: the live client and service by default, fakes in
    /// tests.
    var fetchList: (GitHubClient.ListScope, Int) async throws -> [PullRequestSummary]
    var fetchSummary: (Int) async throws -> PullRequestSummary?
    var fetchHasMergeQueue: () async -> Bool
    var fetchThreads: (Int) async -> [ReviewThread]
    var performCreate: (Worktree, String, String) async throws -> String

    /// Tells GitHub the stack's open pull requests are a stack; run
    /// whenever one opens, since a stack is built one at a time.
    var performLinkStack: (Worktree) async throws -> Void

    /// Merges a stacked pull request and every one below it.
    var performMergeStack: (Worktree, Int) async throws -> Void = { _, _ in
        // Replaced by the initialiser.
    }

    /// The picker's models and the effort a launch without a flag
    /// runs at, for a disclosure of a session started on defaults.
    var launchChoices: (AgentKind) -> (models: [String], defaultEffort: String?) = { _ in ([], nil) }
    /// The repository's default branch, which has no pull request
    /// of its own to look for.
    let defaultBranch: String?

    /// Everything about the stack this branch belongs to: what it
    /// is, and the work it can be asked to do.
    var stacking: StackWork = .init()

    var fetchTemplate: (String) async -> String?
    var fetchCommitMessages: (Worktree, String?) async -> [String]

    /// How many commits the listed entry has of its own, which is
    /// what the push button counts.
    var fetchCommitCount: (Worktree, String?) async -> Int = { _, _ in 0 }
    var generateDescription: ([String]) async -> (title: String, body: String)?
    var fillTemplate: ([String], String) async -> String?
    var performMergeChange: (PullRequestSummary) async throws -> Void
    var performPostMergeCleanup: (Worktree, String) async -> Void
    var fetchCurrentBranch: (String) async -> String?
    var fetchRebaseNeed: (Worktree) async -> SessionService.RebaseNeed
    var performPush: (Worktree) async throws -> PushDestination
    var performRebase: (Worktree) async throws -> Void
    var checkTipSigned: (Worktree) async -> Bool

    /// The visible page. Every scope asks GitHub for one small
    /// listing and no more, so paging walks what is already here
    /// rather than fetching further into a repository with thousands
    /// of open pull requests.
    var page = 0

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

    /// The merge queue answer for the repository, which decides
    /// whether the merge action queues or merges.
    func loadMergeQueue() async {
        hasMergeQueue = await fetchHasMergeQueue()
    }

    /// The cached listing paints instantly while the fetch runs; a
    /// kept selection is re-selected once the fetch answers, and a
    /// single result opens its conversation directly. Extending
    /// keeps the current page and raises the fetch limit.
    /// `refreshingFacts` re-reads what the worktree itself says:
    /// its signing, its rebase need, its template and its stack.
    /// Moving up and down a stack leaves all of that alone, since
    /// every entry shares one worktree, and asking git again is
    /// what made the move feel like a load rather than a click.
    func reload(keepingSelection: Bool = false, refreshingFacts: Bool = true) async {
        let previous = keepingSelection ? selected?.number : nil
        isLoading = true
        // The cache paints before any of the reading: the listing
        // this branch had last time is on screen at once, and the
        // fetch replaces it in place.
        page = 0
        if keepingSelection == false {
            selected = nil
        }
        paintCachedListing()
        // Selected from the cache, not after the fetch: a branch
        // with one pull request opens it the moment the tab does,
        // and clicking between worktrees paints what each had.
        if selected == nil, summaries.count == 1, let only = summaries.first {
            select(only)
        }
        loadDraft()
        if let worktree = branchItem?.worktree {
            if refreshingFacts {
                await refreshWorktreeFacts(worktree)
            } else {
                // An entry switch keeps the worktree's facts but
                // fills the form from this entry's own commits.
                await prefillFromSingleCommit(worktree)
            }
            // The count belongs to the entry, not to the worktree,
            // so an entry switch reads it again.
            commitsAboveBase = await fetchCommitCount(listedWorktree ?? worktree, listedRange)
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
            let limit = GitHubClient.listLimit
            let fetched = try await listing(limit: limit)
            guard Task.isCancelled == false, requested == cacheKey else {
                return
            }

            summaries = Self.worthShowing(fetched)
            fetchedLimit = limit
            pullRequests.rememberListing(
                repositoryPath: repository.path,
                scope: scope.listScope(branch: listedBranch),
                summaries: fetched,
            )
            // A branch with one live pull request opens it: there
            // is nothing else the list could be for.
            let chosen = summaries.first { $0.number == previous }
                ?? (summaries.count == 1 ? summaries.first : nil)
            if let chosen {
                select(chosen)
            }
            ServiceStatus.shared.recordSuccess()
            prefetchStack()
        } catch {
            ServiceStatus.shared.record(failure: error, doing: "Pull requests for " + repository.name)
        }
    }

    // MARK: Private

    // Fetches stay one page ahead of the visible one, so the pager
    // knows whether a next page exists.
}
