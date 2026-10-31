import SanductorDomain

extension SessionService {
    func pushStack(worktree: Worktree, stack: BranchStack) async throws -> [String] {
        let queued = try await pullRequests.queuedBranches(repositoryPath: worktree.repositoryPath)
        let (index, branches) = try stackPushSelection(
            worktree: worktree, stack: stack, queued: queued,
        )
        var pushed = [String]()
        var parent: (branch: String, previousTip: String)?
        for branch in branches {
            if parent == nil, let below = stack.parent(of: branch), queued.contains(below),
               let tip = await git.tip(of: below, worktreePath: worktree.path)
            {
                parent = await (remoteBranchRef(worktreePath: worktree.path, branch: below), tip)
            }
            let remote = await forkRemote(worktreePath: worktree.path, branch: branch)?.remote ?? "origin"
            let previousTip = await git.tip(of: branch, worktreePath: worktree.path)
            // An earlier push's fetch may have pruned a deleted higher branch.
            if stack.branches[...index].contains(branch) == false,
               await git.refExists(worktreePath: worktree.path, ref: "refs/remotes/" + remote + "/" + branch) == false
            {
                continue
            }
            if AppSettings.requiresSignedCommits,
               await git.isCommitSigned(worktreePath: worktree.path, ref: branch) == false
            {
                throw SessionServiceError(
                    branch + "'s tip commit is not GPG signed; Rebase signs the stack before pushing.",
                )
            }

            await progress("Pushing `" + branch + "`")
            try await git.push(
                worktreePath: worktree.path,
                branch: branch,
                remote: remote,
                parent: parent,
            )
            parent = previousTip.map { (branch, $0) }
            pushed.append(branch)
            pullRequests.markChecksPending(repositoryPath: worktree.repositoryPath, branches: [branch])
        }
        return pushed
    }

    private func stackPushSelection(
        worktree: Worktree, stack: BranchStack, queued: Set<String>,
    ) throws -> (Int, [String]) {
        if stack.isStacked {
            try requireStackable(stack)
        }
        guard let index = stack.branches.firstIndex(of: worktree.branch) else {
            throw stackError("The selected branch is no longer in the stack", in: worktree.path)
        }

        let movable = stack.mutableBranches(queued: queued)
        return (index, stack.branchesToPush(through: worktree.branch)
            .filter(movable.contains))
    }
}
