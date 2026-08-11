import AgentIDEData
import AgentIDEDomain
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
    init(worktreePath: String, git: GitClient, baseRefProvider: @escaping () async -> String? = { nil }) {
        self.worktreePath = worktreePath
        self.git = git
        self.baseRefProvider = baseRefProvider
    }

    deinit {
        // Nothing to clean up.
    }

    // MARK: Internal

    /// What the review diffs.
    enum Scope: Hashable {
        /// Uncommitted changes against `HEAD`.
        case uncommitted
        /// The last commit, or uncommitted changes when there are
        /// any and nothing picked uncommitted explicitly.
        case lastCommit
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

    /// The selected lines per file path.
    var selections: [String: Set<DiffSelection>] = [:]

    /// The last action's outcome, for display.
    private(set) var status: String?

    /// The base ref the branch scope last diffed against.
    private(set) var branchBase: String?

    /// The branch scope's commits, newest first, one line each.
    private(set) var branchCommits: [String] = []

    /// The files to display, generated ones filtered unless revealed.
    var visibleFiles: [DiffFile] {
        showsGenerated ? files : files.filter { isGenerated($0.path) == false }
    }

    /// Whether a path looks generated.
    func isGenerated(_ path: String) -> Bool {
        Self.generatedFragments.contains { path.contains($0) }
    }

    /// Loads the scope's diff; the last commit scope prefers
    /// uncommitted changes when there are any.
    func reload() async {
        selections = [:]
        do {
            switch scope {
            case .uncommitted:
                showsUncommitted = true
                files = try await DiffParser.parse(git.uncommittedDiff(worktreePath: worktreePath))

            case .lastCommit:
                let uncommitted = try await git.uncommittedDiff(worktreePath: worktreePath)
                if uncommitted.isEmpty {
                    showsUncommitted = false
                    files = try await DiffParser.parse(git.lastCommitDiff(worktreePath: worktreePath))
                } else {
                    showsUncommitted = true
                    files = DiffParser.parse(uncommitted)
                }

            case .branch:
                showsUncommitted = false
                branchBase = nil
                branchCommits = []
                guard let baseRef = await baseRefProvider() else {
                    status = "No base branch to diff against."
                    files = []
                    return
                }

                // Commits before the diff, so they list even when the
                // diff itself fails to parse.
                branchBase = baseRef
                branchCommits = await git.branchCommits(worktreePath: worktreePath, baseRef: baseRef)
                files = try await DiffParser.parse(git.branchDiff(worktreePath: worktreePath, baseRef: baseRef))
            }
            commitMessage = try await git.lastCommitMessage(worktreePath: worktreePath)
        } catch {
            status = error.localizedDescription
        }
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
            status = error.localizedDescription
        }
    }

    /// Amends the last commit's message.
    func saveCommitMessage() async {
        do {
            try await git.amend(worktreePath: worktreePath, message: commitMessage)
            status = "Commit message updated."
        } catch {
            status = error.localizedDescription
        }
    }

    // MARK: Private

    private let worktreePath: String
    private let git: GitClient
    private let baseRefProvider: () async -> String?
}
