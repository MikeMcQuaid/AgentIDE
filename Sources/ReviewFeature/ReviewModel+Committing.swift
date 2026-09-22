import TerminalUI

/// Which files the next or amended commit carries; split from the
/// model for length.
///
/// `excludedFromCommit` holds what is left out rather than what is
/// in, so a file the agent writes while the pane is open joins the
/// commit instead of being silently dropped from it.
extension ReviewModel {
    var isReadOnly: Bool {
        stackTarget != nil || commitTarget != nil
    }

    var showsCommitTicks: Bool {
        isReadOnly == false && (showsUncommitted || scope == .lastCommit)
    }

    var canAmendLastCommit: Bool {
        scope == .lastCommit && isReadOnly == false && isAmending == false && lastCommitHash != nil
            && (messageEdited || committingCount < files.count)
            && (files.isEmpty || committingCount > 0)
    }

    /// Keeps ticked files in the reviewed commit; excluded changes
    /// remain uncommitted without taking any staged work with them.
    func amendLastCommit() async {
        guard canAmendLastCommit, let lastCommitHash else {
            return
        }

        isAmending = true
        defer { isAmending = false }
        do {
            try await git.amend(
                worktreePath: worktreePath,
                excluding: files.map(\.path).filter { isCommitting($0) == false },
                message: commitMessage,
                expectedHead: lastCommitHash,
            )
            excludedFromCommit = []
            await reload()
            // The tip moved: the sidebar's counts and the pull
            // request pane's Push read it on this reading rather
            // than on the next poll.
            UtilityTabTarget.requestSidebarRefresh()
            setStatus("Amended the last commit.")
        } catch {
            report(error.localizedDescription)
        }
    }

    /// The uncommitted files the next commit will carry, in the
    /// order they are listed. Empty when every file is ticked, which
    /// is what says "the whole worktree" to the service: a commit of
    /// everything must also sweep up anything the diff never listed.
    var pathsToCommit: [String] {
        guard excludedFromCommit.isEmpty == false else {
            return []
        }

        return files.map(\.path).filter { excludedFromCommit.contains($0) == false }
    }

    /// How many files the next commit carries.
    var committingCount: Int {
        files.count { isCommitting($0.path) }
    }

    /// Whether anything is ticked at all. An empty `pathsToCommit`
    /// says "the whole worktree" to the service, and unticking every
    /// file empties it too: the menu bar's own Commit does not ask
    /// the button whether it is dimmed, so the answer has to be
    /// here rather than in the button's state.
    var hasSomethingToCommit: Bool {
        files.isEmpty == false && committingCount > 0
    }

    /// Whether a file is ticked for the next commit.
    func isCommitting(_ path: String) -> Bool {
        excludedFromCommit.contains(path) == false
    }

    /// Ticks or unticks one file.
    func setCommitting(_ committing: Bool, path: String) {
        if committing {
            excludedFromCommit.remove(path)
        } else {
            excludedFromCommit.insert(path)
        }
    }
}
