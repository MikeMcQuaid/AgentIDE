import SanductorData
import SanductorDomain

/// Async reads check their generation before publishing any result.
extension ReviewModel {
    func showCommit(_ commit: String?) async {
        guard isAmending == false else {
            setStatus("Wait for the commit to finish before opening another commit.")
            return
        }

        reloadGeneration += 1
        let generation = reloadGeneration
        hasLoaded = false
        status = nil
        if let commit {
            let resolved = await git.commitHash(of: commit + "^{commit}", worktreePath: worktreePath)
            guard generation == reloadGeneration, Task.isCancelled == false else {
                return
            }
            guard let resolved else {
                hasLoaded = true
                setStatus("Commit " + commit + " is not available in this worktree.")
                return
            }

            commitTarget = resolved
        } else {
            commitTarget = nil
        }
        await reload()
    }

    func reload() async {
        reloadGeneration += 1
        let generation = reloadGeneration
        selections = [:]
        do {
            if let commitTarget {
                try await loadCommit(commitTarget, generation: generation)
            } else if let stackTarget {
                try await loadStackEntry(parent: stackTarget.parent, branch: stackTarget.branch, generation: generation)
            } else {
                try await loadScope(generation: generation)
                try checkReload(generation)
                if showsUncommitted {
                    // Keep typed messages, but never carry an unedited commit's
                    // message into new, uncommitted work.
                    if messageEdited == false {
                        commitMessage = ""
                    }
                    originalMessage = ""
                } else if scope != .lastCommit {
                    let message = try await git.commitMessage(worktreePath: worktreePath, commit: "HEAD")
                    try checkReload(generation)
                    if messageEdited == false {
                        commitMessage = message
                    }
                    originalMessage = message
                }
                let threads = await fetchThreads()
                try checkReload(generation)
                self.threads = threads
            }
            await recordReload(nil, generation: generation)
        } catch {
            await recordReload(error, generation: generation)
        }
        guard generation == reloadGeneration, Task.isCancelled == false else {
            return
        }

        hasLoaded = true
    }

    private func checkReload(_ generation: Int) throws {
        guard generation == reloadGeneration else {
            throw CancellationError()
        }

        try Task.checkCancellation()
    }

    func loadLastCommit(generation: Int) async throws {
        let head = await git.commitHash(of: "HEAD", worktreePath: worktreePath)
        try checkReload(generation)
        let committed = try await DiffParser.parse(git.commitDiff(
            worktreePath: worktreePath,
            commit: head ?? "HEAD",
            ignoringWhitespace: hidesWhitespace,
        ))
        try checkReload(generation)
        let message = try await git.commitMessage(worktreePath: worktreePath, commit: head ?? "HEAD")
        try checkReload(generation)
        localReviewContext = "commit " + (head ?? "HEAD") + "\n" + message
        showsUncommitted = false
        if lastCommitHash != head {
            excludedFromCommit = []
        }
        lastCommitHash = head
        files = committed
        if messageEdited == false {
            commitMessage = message
        }
        originalMessage = message
    }

    private func loadScope(generation: Int) async throws {
        let currentBranch = await git.currentBranch(worktreePath: worktreePath)
        try checkReload(generation)
        let hasUpstream =
            if let currentBranch {
                await git.remoteBranchExists(worktreePath: worktreePath, branch: currentBranch)
            } else {
                false
            }
        try checkReload(generation)
        self.hasUpstream = hasUpstream
        switch scope {
        case .uncommitted:
            let uncommitted = try await DiffParser.parse(git.uncommittedDiff(
                worktreePath: worktreePath,
                ignoringWhitespace: hidesWhitespace,
            ))
            try checkReload(generation)
            showsUncommitted = true
            files = uncommitted
            localReviewContext = ""

        case .lastCommit:
            try await loadLastCommit(generation: generation)

        case .upstream:
            showsUncommitted = false
            try await loadUpstream(currentBranch: currentBranch, generation: generation)

        case .branch:
            showsUncommitted = false
            try await loadBranch(generation: generation)
        }
        try checkReload(generation)
    }

    /// The upstream scope stays empty until the branch has been pushed.
    private func loadUpstream(currentBranch: String?, generation: Int) async throws {
        branchCommits = []
        localReviewContext = ""
        guard let currentBranch, hasUpstream else {
            if currentBranch != nil {
                setStatus("This branch has not been pushed yet.")
            }
            files = []
            return
        }

        // Bound by the base, so rebasing never shows the base's changes.
        let upstreamRef = "origin/" + currentBranch
        let baseRef = await baseRefProvider()
        try checkReload(generation)
        let commits = await git.unpushedCommitLines(
            worktreePath: worktreePath, upstreamRef: upstreamRef, baseRef: baseRef,
        )
        try checkReload(generation)
        branchCommits = commits
        let context = try await git.reviewCommitContext(
            worktreePath: worktreePath,
            revisions: commits.dropLast().compactMap { $0.split(separator: " ").first.map(String.init) },
        )
        try checkReload(generation)
        localReviewContext = context
        let files = try await DiffParser.parse(git.upstreamDiff(
            worktreePath: worktreePath,
            upstreamRef: upstreamRef,
            baseRef: baseRef,
            ignoringWhitespace: hidesWhitespace,
        ))
        try checkReload(generation)
        self.files = files
    }

    /// One stack entry's own changes, read-only.
    private func loadStackEntry(parent: String, branch: String, generation: Int) async throws {
        branchCommits = []
        showsUncommitted = false
        let context = try await git.reviewCommitContext(
            worktreePath: worktreePath, revisions: [parent + ".." + branch],
        )
        try checkReload(generation)
        localReviewContext = context
        let files = try await DiffParser.parse(git.stackDiff(
            worktreePath: worktreePath,
            parent: parent,
            branch: branch,
            ignoringWhitespace: hidesWhitespace,
        ))
        try checkReload(generation)
        self.files = files
        let message = try await git.commitMessage(worktreePath: worktreePath, commit: branch)
        try checkReload(generation)
        commitMessage = message
        originalMessage = message
    }

    /// One commit's diff and message, neither of which the pane writes back.
    private func loadCommit(_ commit: String, generation: Int) async throws {
        branchCommits = []
        showsUncommitted = false
        let files = try await DiffParser.parse(git.commitDiff(
            worktreePath: worktreePath,
            commit: commit,
            ignoringWhitespace: hidesWhitespace,
        ))
        try checkReload(generation)
        self.files = files
        let message = try await git.commitMessage(worktreePath: worktreePath, commit: commit)
        try checkReload(generation)
        commitMessage = message
        localReviewContext = "commit " + commit + "\n" + message
        originalMessage = message
    }

    /// Commits load first so they list even when the branch diff fails.
    private func loadBranch(generation: Int) async throws {
        branchCommits = []
        localReviewContext = ""
        let baseRef = await baseRefProvider()
        try checkReload(generation)
        guard let baseRef else {
            setStatus("No base branch to diff against.")
            files = []
            return
        }

        let commits = await git.branchCommits(worktreePath: worktreePath, baseRef: baseRef)
        try checkReload(generation)
        branchCommits = commits
        let context = try await git.reviewCommitContext(
            worktreePath: worktreePath,
            revisions: commits.dropLast().compactMap { $0.split(separator: " ").first.map(String.init) },
        )
        try checkReload(generation)
        localReviewContext = context
        let files = try await DiffParser.parse(git.branchDiff(
            worktreePath: worktreePath,
            baseRef: baseRef,
            ignoringWhitespace: hidesWhitespace,
        ))
        try checkReload(generation)
        self.files = files
    }
}
