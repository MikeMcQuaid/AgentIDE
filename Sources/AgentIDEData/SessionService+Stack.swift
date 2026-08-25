import AgentIDEDomain
import Foundation

/// Stacked branches, all in one worktree: each built on the one
/// below, the bottom on the repository's default branch. The stack is
/// derived from ancestry every time it is asked for, so a branch an
/// agent cuts for itself belongs to the stack as surely as one this
/// app made, and nothing has to be remembered anywhere.
public extension SessionService {
    /// The stack the worktree's branch belongs to, bottom first.
    /// A branch with nothing under or over it comes back as a stack
    /// of one, which every surface treats as no stack at all.
    func stack(for worktree: Worktree) async -> BranchStack {
        let path = worktree.path
        let checkedOut = await git.currentBranch(worktreePath: path) ?? worktree.branch
        let repository = Repository(name: worktree.repositoryName, path: worktree.repositoryPath)
        let baseRef = await git.defaultBaseRef(of: repository)
        let base = baseRef.map(Self.branchName(fromBaseRef:))
        guard let baseRef else {
            return BranchStack(base: nil, branches: [checkedOut], checkedOut: checkedOut)
        }

        var related = [(branch: String, fork: Int, tip: Int)]()
        for branch in await git.branches(worktreePath: path) where branch != base {
            guard await git.isAncestor(baseRef, of: branch, worktreePath: path) else {
                continue
            }

            // Related when the two last shared history beyond the
            // default branch: one was cut from the other. Ancestry
            // alone is not enough, since a branch that has gained a
            // commit since its child forked is no longer the child's
            // ancestor, and that is exactly when a stack needs
            // putting back in order.
            let fork = branch == checkedOut
                ? await git.tip(of: branch, worktreePath: path)
                : await git.mergeBase(branch, checkedOut, worktreePath: path)
            guard let fork, await git.isAncestor(fork, of: baseRef, worktreePath: path) == false else {
                continue
            }

            await related.append((
                branch,
                git.commitCount(from: baseRef, to: fork, worktreePath: path),
                git.commitCount(from: baseRef, to: branch, worktreePath: path),
            ))
        }
        // Ordered by where each forks from the line of work, then by
        // how far it has come: that is the order they were built in
        // and the order they must be rebased in.
        let branches = related
            .sorted { ($0.fork, $0.tip) < ($1.fork, $1.tip) }
            .map(\.branch)
        return BranchStack(
            base: base,
            branches: branches.isEmpty ? [checkedOut] : branches,
            checkedOut: checkedOut,
        )
    }

    /// The branches a restack would actually move: those not
    /// already sitting on the one below them. Empty means the stack
    /// is in order and the button has nothing to do.
    func branchesOutOfPlace(worktree: Worktree) async -> [String] {
        let path = worktree.path
        let stack = await stack(for: worktree)
        guard let base = stack.base else {
            return []
        }

        var pending = [String]()
        for branch in stack.branches {
            let parent = stack.parent(of: branch) ?? base
            if await git.isAncestor(parent, of: branch, worktreePath: path) == false {
                pending.append(branch)
            }
        }
        return pending
    }

    /// The branches a stack push would actually send: those with
    /// commits the remote does not carry, or no remote branch yet.
    func branchesUnpushed(worktree: Worktree) async -> [String] {
        let path = worktree.path
        let stack = await stack(for: worktree)
        var pending = [String]()
        for branch in stack.branches {
            let remote = "refs/remotes/origin/" + branch
            guard await git.refExists(worktreePath: path, ref: remote) else {
                pending.append(branch)
                continue
            }

            if await git.commitCount(from: remote, to: branch, worktreePath: path) > 0 {
                pending.append(branch)
            }
        }
        return pending
    }

    /// Puts every branch of a stack back on the one below it, bottom
    /// up, signing each commit it replays. A branch already sitting
    /// on its parent is left alone rather than rewritten: an
    /// unnecessary rebase changes every commit's name for nothing.
    /// Nothing half-done survives a failure: the branches already
    /// moved go back to where they were and the worktree returns to
    /// the branch it started on.
    func restack(worktree: Worktree) async throws -> [String] {
        let path = worktree.path
        let stack = await stack(for: worktree)
        try await requireQuiet(worktree: worktree, action: "restack")
        guard let base = stack.base else {
            throw stackError("No default branch to stack on", in: path)
        }

        var tips = [String: String]()
        for branch in stack.branches {
            tips[branch] = await git.tip(of: branch, worktreePath: path)
        }

        var moved = [String]()
        do {
            for branch in stack.branches {
                let parent = stack.parent(of: branch) ?? base
                // Already on its parent: leave every commit's name
                // alone rather than rewriting them to say so.
                if await git.isAncestor(parent, of: branch, worktreePath: path) {
                    continue
                }
                // Where it forked from, recorded before anything
                // moved: without it the replay takes the parent's
                // own commits along a second time.
                guard let forkedFrom = tips[parent] else {
                    continue
                }

                await progress("Rebasing `" + branch + "` onto `" + parent + "`")
                try await git.rebaseSigned(
                    branch: branch,
                    onto: parent,
                    from: forkedFrom,
                    worktreePath: path,
                )
                moved.append(branch)
            }
        } catch {
            await progress("Putting the stack back as it was")
            for branch in moved.reversed() {
                if let tip = tips[branch] {
                    try? await git.reset(branch: branch, to: tip, worktreePath: path)
                }
            }
            try? await git.checkout(branch: stack.checkedOut, worktreePath: path)
            throw error
        }

        try await git.checkout(branch: stack.checkedOut, worktreePath: path)
        return moved
    }

    /// Pushes every branch of a stack, bottom up, so each pull
    /// request's base is on the remote before the branch that points
    /// at it. Each push carries the lease and the includes check the
    /// single-branch push does.
    func pushStack(worktree: Worktree) async throws -> [String] {
        let stack = await stack(for: worktree)
        var pushed = [String]()
        for branch in stack.branches {
            await progress("Pushing `" + branch + "`")
            try await git.push(worktreePath: worktree.path, branch: branch)
            pushed.append(branch)
        }
        return pushed
    }

    /// Cuts a new branch on top of the checked-out one, in the same
    /// worktree, which is how a stack grows: the session carries on
    /// where it was, now building on what it just finished.
    func stackBranch(named name: String, on worktree: Worktree) async throws {
        try await requireQuiet(worktree: worktree, action: "branch")
        await progress("Creating `" + name + "` on `" + worktree.branch + "`")
        try await git.createBranch(named: name, worktreePath: worktree.path)
    }

    // MARK: Internal

    /// Refuses while the worktree holds uncommitted work: a stack
    /// moves by checking branches out, which would take those
    /// changes with it or refuse half way.
    internal func requireQuiet(worktree: Worktree, action _: String) async throws {
        guard await git.isDirty(worktreePath: worktree.path) else {
            return
        }

        throw stackError("Commit or discard the worktree's changes first", in: worktree.path)
    }

    private func stackError(_ message: String, in path: String) -> CommandError {
        CommandError(
            command: "stack in " + path,
            result: ProcessResult(status: 1, standardOutput: "", standardError: message),
        )
    }
}
