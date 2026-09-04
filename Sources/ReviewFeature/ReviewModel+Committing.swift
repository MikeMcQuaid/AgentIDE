/// Which uncommitted files the next commit carries; split from the
/// model for length.
///
/// `excludedFromCommit` holds what is left out rather than what is
/// in, so a file the agent writes while the pane is open joins the
/// commit instead of being silently dropped from it.
extension ReviewModel {
    var isReadOnly: Bool {
        stackTarget != nil || commitTarget != nil
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
