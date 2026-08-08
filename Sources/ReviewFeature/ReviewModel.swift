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

    /// Creates a review model for a worktree.
    init(worktreePath: String, git: GitClient) {
        self.worktreePath = worktreePath
        self.git = git
    }

    deinit {
        // Nothing to clean up.
    }

    // MARK: Internal

    /// Path fragments treated as generated and hidden by default.
    static let generatedFragments = [
        ".pbxproj", "Package.resolved", ".lock", "Gemfile.lock", ".xcassets",
    ]

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

    /// The files to display, generated ones filtered unless revealed.
    var visibleFiles: [DiffFile] {
        showsGenerated ? files : files.filter { isGenerated($0.path) == false }
    }

    /// Whether a path looks generated.
    func isGenerated(_ path: String) -> Bool {
        Self.generatedFragments.contains { path.contains($0) }
    }

    /// Loads the diff, preferring uncommitted changes.
    func reload() async {
        selections = [:]
        do {
            let uncommitted = try await git.uncommittedDiff(worktreePath: worktreePath)
            if uncommitted.isEmpty {
                showsUncommitted = false
                files = try await DiffParser.parse(git.lastCommitDiff(worktreePath: worktreePath))
            } else {
                showsUncommitted = true
                files = DiffParser.parse(uncommitted)
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
}
