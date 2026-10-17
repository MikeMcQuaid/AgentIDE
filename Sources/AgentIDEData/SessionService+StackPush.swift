import AgentIDEDomain

extension SessionService {
    /// Autofix fixes the selected branch's destination, lease and reviewed commit.
    struct PinnedBranchPush {
        let remote: String
        let expectedTip: String
        let commit: String
        let previousTip: String
    }

    func pushStack(worktree: Worktree, stack: BranchStack, pinned: PinnedBranchPush? = nil) async throws -> [String] {
        if stack.isStacked {
            try requireStackable(stack)
        }
        guard let index = stack.branches.firstIndex(of: worktree.branch) else {
            throw stackError("The selected branch is no longer in the stack", in: worktree.path)
        }

        if let pinned, index > 0,
           await git.isAncestor(stack.branches[index - 1], of: pinned.commit, worktreePath: worktree.path) == false
        {
            throw SessionServiceError("The stack's base changed; restack and review before automatic pushing")
        }

        var pushed = [String]()
        var parent: (branch: String, previousTip: String)?
        for branch in stack.branchesToPush(through: worktree.branch).dropFirst(pinned == nil ? 0 : index) {
            let selected = branch == worktree.branch ? pinned : nil
            let remote: String
            let previousTip: String?
            if let selected {
                remote = selected.remote
                previousTip = selected.previousTip
            } else {
                remote = await forkRemote(worktreePath: worktree.path, branch: branch)?.remote ?? "origin"
                previousTip = await git.tip(of: branch, worktreePath: worktree.path)
            }
            // An earlier push's fetch may have pruned a deleted higher branch.
            if stack.branches[...index].contains(branch) == false,
               await git.refExists(worktreePath: worktree.path, ref: "refs/remotes/" + remote + "/" + branch) == false
            {
                continue
            }
            if AppSettings.requiresSignedCommits,
               await git.isCommitSigned(worktreePath: worktree.path, ref: selected?.commit ?? branch) == false
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
                expectedTip: selected?.expectedTip,
                sourceCommit: selected?.commit,
                parent: selected == nil ? parent : nil,
            )
            parent = previousTip.map { (branch, $0) }
            pushed.append(branch)
            pullRequests.markChecksPending(repositoryPath: worktree.repositoryPath, branches: [branch])
        }
        return pushed
    }
}
