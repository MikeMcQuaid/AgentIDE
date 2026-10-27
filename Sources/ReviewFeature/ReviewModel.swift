import AgentIDEData
import AgentIDEDomain
import Foundation
import Observation

/// Loads a worktree's diff, tracks per-line selections and applies
/// rejections and amendments.
@preconcurrency
@Observable
@MainActor
final class ReviewModel {
    // MARK: Lifecycle

    /// Creates a review model for a worktree; `baseRefProvider`
    /// resolves the whole-branch scope's merge base on demand.
    init(
        worktreePath: String,
        repositoryName: String,
        git: GitClient,
        baseRefProvider: @escaping () async -> String? = { nil },
        draftMessage: @escaping () async -> String? = { nil },
        fetchThreads: @escaping () async -> [ReviewThread] = { [] },
        setThreadResolved: @escaping (String, Bool) async throws -> Void = { _, _ in
            // Without GitHub wiring resolve toggles are no-ops.
        },
    ) {
        self.worktreePath = worktreePath
        self.repositoryName = repositoryName
        self.git = git
        scope = Self.rememberedScope(for: worktreePath)
        self.draftMessage = draftMessage
        self.baseRefProvider = baseRefProvider
        self.fetchThreads = fetchThreads
        self.setThreadResolved = setThreadResolved
    }

    deinit {
        // Nothing to clean up.
    }

    // MARK: Internal

    /// The repository this worktree belongs to, as the sidebar names
    /// it, so its messages say which repository they are about.
    let repositoryName: String
    let draftMessage: () async -> String?

    /// The parsed diff files.
    var files: [DiffFile] = []

    /// The immutable commit messages captured with the displayed diff.
    var localReviewContext = ""

    /// Whether any scope has loaded yet; before, progress shows.
    var hasLoaded = false

    /// Updated by the status extension when a failed read finds missing Git metadata.
    var isRepositoryAvailable = true

    /// Whether the diff shows uncommitted changes.
    var showsUncommitted = false

    /// See `ReviewModel+Committing`.
    var excludedFromCommit: Set<String> = []

    var lastCommitHash: String?
    var isAmending = false

    /// Set only by the find extension, which recounts them.
    var findTargets: [FindTarget] = []
    var currentFind = 0

    /// The commit message being edited.
    var commitMessage = ""

    /// The selected lines per file path.
    var selections: [String: Set<DiffSelection>] = [:]

    /// The last action's outcome, for display.
    var status: String?

    /// The branch scope's commits, newest first, one line each.
    var branchCommits: [String] = []

    /// The branch's open pull request conversations, shown inline
    /// under the files they anchor to.
    var threads: [ReviewThread] = []

    /// Whether the checked-out branch has its own origin ref, so
    /// the upstream scope has something to diff against; refreshed
    /// on every reload.
    var hasUpstream = false

    let worktreePath: String

    var resolveOnPush: ((ReviewThread) throws -> Void)?
    var pendingResolution: (ReviewThread) -> Bool = { _ in false }

    /// Test seam: whether the worktree's directory still exists,
    /// which decides if a reload failure is worth reporting; the
    /// real file system by default.
    var worktreeExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }

    /// Internal, since the edits extension file resets files through it.
    let git: GitClient

    let fetchThreads: () async -> [ReviewThread]
    let setThreadResolved: (String, Bool) async throws -> Void

    /// Shared with the reload and status extensions; not display state.
    @ObservationIgnored var reloadGeneration = 0

    let baseRefProvider: () async -> String?

    /// The commit's actual message, shared with the reload extension.
    var originalMessage = ""

    /// Whether whitespace-only changes are hidden from the diff.
    var hidesWhitespace = false {
        didSet { reloadGeneration += 1 }
    }

    /// A stack entry this pane is showing instead of the worktree's
    /// own diff: the branch and what it is built on. Nil is the
    /// ordinary case, where the pane shows the branch that is
    /// checked out and can be written to.
    var stackTarget: (parent: String, branch: String)? {
        didSet { reloadGeneration += 1 }
    }

    /// One commit from the listing, shown on its own: the same view
    /// the last-commit scope gives, with its message read-only
    /// because amending reaches the tip and nothing else.
    var commitTarget: String? {
        didSet {
            reloadGeneration += 1
            if oldValue == nil, commitTarget != nil {
                messageBeforeCommit = (commitMessage, originalMessage)
            } else if commitTarget == nil, let messageBeforeCommit {
                commitMessage = messageBeforeCommit.edited
                originalMessage = messageBeforeCommit.original
                self.messageBeforeCommit = nil
            }
        }
    }

    /// The review scope; per-line rejection and message amendment
    /// only apply to the last commit.
    var scope: Scope = .lastCommit {
        didSet {
            if oldValue != scope {
                reloadGeneration += 1
                excludedFromCommit = []
            }
            remember(scope)
        }
    }

    // Whether what is shown can only be read: a branch this
    // worktree does not hold, or a commit further back than the
    // last one. Either way rejecting lines or amending would have
    // to rewrite history that is not the tip in front of you.

    /// Whether the commit message differs from the commit's actual
    /// message, so Amend only lights up with something to amend.
    var messageEdited: Bool {
        commitMessage != originalMessage
    }

    /// The find bar's query; the hunks holding a match and which of
    /// them is showing are derived from it.
    var findQuery = "" {
        didSet { updateFindTargets() }
    }

    /// Reverse-applies every selected line and, when reviewing the
    /// last commit, amends it.
    func rejectSelected() async {
        do {
            for file in files {
                guard let selection = selections[file.path], selection.isEmpty == false,
                      let patch = PatchBuilder.reversePatch(file: file, selection: selection)
                else {
                    continue
                }

                try await git.applyReverse(patch: patch, worktreePath: worktreePath)
            }
            if showsUncommitted == false {
                try await git.amend(worktreePath: worktreePath, message: nil)
            }
            setStatus("Rejected selected lines.")
            await reload()
        } catch {
            report(error.localizedDescription)
        }
    }

    // MARK: Private

    @ObservationIgnored private var messageBeforeCommit: (edited: String, original: String)?
}
