import AgentIDEData
import AgentIDEDomain
import Foundation
import Observation
import TerminalUI

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

    /// What the review diffs. Each scope always shows its own diff,
    /// so switching between them reliably changes the display.
    enum Scope: Hashable {
        /// Uncommitted changes against `HEAD`.
        case uncommitted
        /// The last commit.
        case lastCommit
        /// Commits not yet on the branch's own origin ref; only
        /// available once the branch has been pushed.
        case upstream
        /// Every commit on the branch against its merge base: the
        /// open pull request's base branch, or the default branch.
        case branch
    }

    /// The repository this worktree belongs to, as the sidebar names
    /// it, so its messages say which repository they are about.
    let repositoryName: String

    /// The parsed diff files.
    private(set) var files: [DiffFile] = []

    /// Whether any scope has loaded yet; before, progress shows.
    private(set) var hasLoaded = false

    /// Whether the diff shows uncommitted changes; rejection amends committed ones only.
    private(set) var showsUncommitted = false

    /// See `ReviewModel+Committing`.
    var excludedFromCommit: Set<String> = []

    /// Set only by the find extension, which recounts them.
    var findTargets: [FindTarget] = []
    var currentFind = 0

    /// The commit message being edited.
    var commitMessage = ""

    /// Whether whitespace-only changes are hidden from the diff.
    var hidesWhitespace = false

    /// The selected lines per file path.
    var selections: [String: Set<DiffSelection>] = [:]

    /// Typing in a diff line, by the edits extension's key.
    var lineDrafts: [String: String] = [:]

    /// The last action's outcome, for display.
    var status: String?

    /// The branch scope's commits, newest first, one line each.
    private(set) var branchCommits: [String] = []

    /// The branch's open pull request conversations, shown inline
    /// under the files they anchor to.
    private(set) var threads: [ReviewThread] = []

    /// Whether the checked-out branch has its own origin ref, so
    /// the upstream scope has something to diff against; refreshed
    /// on every reload.
    private(set) var hasUpstream = false

    /// A stack entry this pane is showing instead of the worktree's
    /// own diff: the branch and what it is built on. Nil is the
    /// ordinary case, where the pane shows the branch that is
    /// checked out and can be written to.
    var stackTarget: (parent: String, branch: String)?

    /// One commit from the listing, shown on its own: the same view
    /// the last-commit scope gives, with its message read-only
    /// because amending reaches the tip and nothing else.
    var commitTarget: String?

    let worktreePath: String

    /// Test seam: whether the worktree's directory still exists,
    /// which decides if a reload failure is worth reporting; the
    /// real file system by default.
    var worktreeExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }

    /// The review scope; per-line rejection and message amendment
    /// only apply to the last commit.
    var scope: Scope = .lastCommit {
        didSet { remember(scope) }
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

    /// Flips one conversation's resolved state on GitHub, then
    /// refreshes the inline listing.
    func toggleResolved(_ thread: ReviewThread) async {
        do {
            try await setThreadResolved(thread.resolveID, thread.isResolved == false)
            threads = await fetchThreads()
        } catch {
            report(error.localizedDescription)
        }
        hasLoaded = true
    }

    /// Loads the scope's diff.
    func reload() async {
        selections = [:]
        if await loadedTarget() {
            hasLoaded = true
            return
        }

        let currentBranch = await git.currentBranch(worktreePath: worktreePath)
        hasUpstream =
            if let currentBranch {
                await git.remoteBranchExists(worktreePath: worktreePath, branch: currentBranch)
            } else {
                false
            }
        do {
            switch scope {
            case .uncommitted:
                showsUncommitted = true
                files = try await DiffParser.parse(git.uncommittedDiff(
                    worktreePath: worktreePath,
                    ignoringWhitespace: hidesWhitespace,
                ))

            case .lastCommit:
                showsUncommitted = false
                files = try await DiffParser.parse(git.lastCommitDiff(
                    worktreePath: worktreePath,
                    ignoringWhitespace: hidesWhitespace,
                ))

            case .upstream:
                showsUncommitted = false
                try await loadUpstream(currentBranch: currentBranch)

            case .branch:
                showsUncommitted = false
                try await loadBranch()
            }
            // Uncommitted work has no message yet: prefilling the
            // last commit's invited amending it by accident, so the
            // field stays as typed and the sparkles button drafts one.
            if showsUncommitted {
                // Switching scopes must not carry a commit's message
                // into uncommitted work, where Commit would reuse it;
                // anything typed here survives, since only an
                // unedited message came from a commit.
                if messageEdited == false {
                    commitMessage = ""
                }
                originalMessage = ""
            } else {
                commitMessage = try await git.lastCommitMessage(worktreePath: worktreePath)
                originalMessage = commitMessage
            }
            threads = await fetchThreads()
        } catch {
            // A worktree can vanish between the poll that mounted
            // this pane and the reload that reads it (a branch
            // renamed away, cleanup after a merge): that is the
            // workspace changing, not a failure, and the sidebar
            // drops the row on its own.
            if worktreeExists(worktreePath) {
                report(error.localizedDescription)
            }
        }
        hasLoaded = true
    }

    /// Fills the commit message from the uncommitted diff using the
    /// on-device model; false when it could not help, so the caller
    /// can show the errors surface. Only ever fills a blank field.
    func generateCommitMessage() async -> Bool {
        guard commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return true
        }
        guard let drafted = await draftMessage() else {
            report("The on-device model could not draft a commit message for these changes.")
            return false
        }

        commitMessage = drafted
        return true
    }

    /// Shows a status in the footer and keeps it in the messages
    /// pane, where a line that scrolls past can still be read.
    func setStatus(_ message: String) {
        status = message
        ErrorLog.shared.note(message, about: repositoryName)
    }

    /// Toggles one line's selection.
    func toggle(file: DiffFile, selection: DiffSelection) {
        var set = selections[file.path] ?? []
        if set.remove(selection) == nil {
            set.insert(selection)
        }
        selections[file.path] = set
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

    /// Amends the last commit's message.
    func saveCommitMessage() async {
        do {
            try await git.amend(worktreePath: worktreePath, message: commitMessage)
            originalMessage = commitMessage
            setStatus("Commit message updated.")
        } catch {
            report(error.localizedDescription)
        }
    }

    // MARK: Private

    /// The commit's actual message, for dimming Amend until the
    /// editor differs from it.
    private var originalMessage = ""

    private let git: GitClient
    private let draftMessage: () async -> String?
    private let baseRefProvider: () async -> String?
    private let fetchThreads: () async -> [ReviewThread]
    private let setThreadResolved: (String, Bool) async throws -> Void

    /// The upstream scope's commits and two-dot diff, empty with a
    /// message until the branch has been pushed.
    private func loadUpstream(currentBranch: String?) async throws {
        branchCommits = []
        guard let currentBranch, hasUpstream else {
            setStatus("This branch has not been pushed yet.")
            files = []
            return
        }

        let upstreamRef = "origin/" + currentBranch
        branchCommits = await git.branchCommits(worktreePath: worktreePath, baseRef: upstreamRef)
        files = try await DiffParser.parse(git.upstreamDiff(
            worktreePath: worktreePath,
            upstreamRef: upstreamRef,
            ignoringWhitespace: hidesWhitespace,
        ))
    }

    /// The branch scope's commits and merge-base diff; commits load
    /// first so they list even when the diff fails to parse.
    /// One stack entry's own changes, read-only: the commits it
    /// adds to the branch below it.
    private func loadStackEntry(parent: String, branch: String) async {
        branchCommits = []
        showsUncommitted = false
        do {
            files = try await DiffParser.parse(git.stackDiff(
                worktreePath: worktreePath,
                parent: parent,
                branch: branch,
                ignoringWhitespace: hidesWhitespace,
            ))
            // The entry's own tip commit, shown as the last-commit
            // scope shows one, read-only: amending reaches the
            // checked-out tip and nothing else.
            commitMessage = try await git.commitMessage(worktreePath: worktreePath, commit: branch)
            originalMessage = commitMessage
        } catch {
            report(error.localizedDescription)
        }
    }

    /// One commit or one stack entry, when the pane has been pointed
    /// at something other than the branch in front of it; false when
    /// it has not, and the scope loads as usual.
    private func loadedTarget() async -> Bool {
        if let commitTarget {
            await loadCommit(commitTarget)
            return true
        }
        if let stackTarget {
            await loadStackEntry(parent: stackTarget.parent, branch: stackTarget.branch)
            return true
        }

        return false
    }

    /// One commit on its own: its diff and its message, neither of
    /// which this pane will write back.
    private func loadCommit(_ commit: String) async {
        branchCommits = []
        showsUncommitted = false
        do {
            files = try await DiffParser.parse(git.commitDiff(
                worktreePath: worktreePath,
                commit: commit,
                ignoringWhitespace: hidesWhitespace,
            ))
            commitMessage = try await git.commitMessage(worktreePath: worktreePath, commit: commit)
            originalMessage = commitMessage
        } catch {
            report(error.localizedDescription)
        }
    }

    private func loadBranch() async throws {
        branchCommits = []
        guard let baseRef = await baseRefProvider() else {
            setStatus("No base branch to diff against.")
            files = []
            return
        }

        branchCommits = await git.branchCommits(worktreePath: worktreePath, baseRef: baseRef)
        files = try await DiffParser.parse(git.branchDiff(
            worktreePath: worktreePath,
            baseRef: baseRef,
            ignoringWhitespace: hidesWhitespace,
        ))
    }
}
