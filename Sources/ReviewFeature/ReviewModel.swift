import AgentIDEData
import AgentIDEDomain
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
    init(worktreePath: String, git: GitClient, baseRefProvider: @escaping () async -> String? = { nil }) {
        self.worktreePath = worktreePath
        self.git = git
        self.baseRefProvider = baseRefProvider
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

    /// Path fragments treated as generated and hidden by default.
    static let generatedFragments = [
        ".pbxproj", "Package.resolved", ".lock", "Gemfile.lock", ".xcassets",
    ]

    /// The review scope; per-line rejection and message amendment
    /// only apply to the last commit.
    var scope: Scope = .lastCommit

    /// The parsed diff files.
    private(set) var files: [DiffFile] = []

    /// Whether the diff shows uncommitted changes (true) or the last
    /// commit (false); rejection amends only in the latter mode.
    private(set) var showsUncommitted = false

    /// The commit message being edited.
    var commitMessage = ""

    /// Whether generated files are revealed.
    var showsGenerated = false

    /// Whether whitespace-only changes are hidden from the diff.
    var hidesWhitespace = false

    /// The selected lines per file path.
    var selections: [String: Set<DiffSelection>] = [:]

    /// The last action's outcome, for display.
    private(set) var status: String?

    /// The branch scope's commits, newest first, one line each.
    private(set) var branchCommits: [String] = []

    /// Whether the checked-out branch has its own origin ref, so
    /// the upstream scope has something to diff against; refreshed
    /// on every reload.
    private(set) var hasUpstream = false

    /// Whether the commit message differs from the commit's actual
    /// message, so Amend only lights up with something to amend.
    var messageEdited: Bool {
        commitMessage != originalMessage
    }

    /// The files to display, generated ones filtered unless revealed.
    var visibleFiles: [DiffFile] {
        showsGenerated ? files : files.filter { isGenerated($0.path) == false }
    }

    /// Whether a path looks generated.
    func isGenerated(_ path: String) -> Bool {
        Self.generatedFragments.contains { path.contains($0) }
    }

    /// Loads the scope's diff.
    func reload() async {
        selections = [:]
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
            commitMessage = try await git.lastCommitMessage(worktreePath: worktreePath)
            originalMessage = commitMessage
        } catch {
            report(error.localizedDescription)
        }
    }

    /// Reports a failure into the app-wide error log; the local
    /// status line keeps success reports only.
    func report(_ message: String) {
        ErrorLog.shared.report(message)
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
            status = "Rejected selected lines."
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
            status = "Commit message updated."
        } catch {
            report(error.localizedDescription)
        }
    }

    // MARK: Private

    /// The commit's actual message, for dimming Amend until the
    /// editor differs from it.
    private var originalMessage = ""

    private let worktreePath: String
    private let git: GitClient
    private let baseRefProvider: () async -> String?

    /// The upstream scope's commits and two-dot diff, empty with a
    /// message until the branch has been pushed.
    private func loadUpstream(currentBranch: String?) async throws {
        branchCommits = []
        guard let currentBranch, hasUpstream else {
            status = "This branch has not been pushed yet."
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
    private func loadBranch() async throws {
        branchCommits = []
        guard let baseRef = await baseRefProvider() else {
            status = "No base branch to diff against."
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
