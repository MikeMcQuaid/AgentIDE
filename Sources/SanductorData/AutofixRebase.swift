// MARK: - AutofixRebase

/// The fetched target of an authorised local conflict rebase.
public struct AutofixRebase: Codable, Equatable, Sendable {
    let baseBranch: String
    let baseHead: String

    var remoteRef: String {
        "origin/" + baseBranch
    }

    func prompt(branch: String, head: String) -> String {
        """
        Resolve upstream merge conflicts by performing a rebase on \(remoteRef).
        Verify the checked-out branch is \(branch) and HEAD is \(head) before starting.
        The worktree has been fetched. Verify \(remoteRef) still identifies \(baseHead) before starting.
        Run: git -c commit.gpgsign=false rebase \(remoteRef.shellQuoted) \(branch.shellQuoted)
        Resolve conflicts, preserving existing fixes, and stage the resolved files.
        Continue with GIT_EDITOR=true git -c commit.gpgsign=false rebase --continue until the rebase finishes.
        Run relevant local checks and report the resulting HEAD. Do not push or request reviews.
        """
    }
}

// MARK: - PullRequestAutomation

extension PullRequestAutomation {
    func acceptsFeedback(from head: String, contains: (String) async -> Bool) async -> Bool {
        if await contains(head) {
            return true
        }
        guard let rebased = rebasedHeads[head] else {
            return false
        }

        return await contains(rebased)
    }
}
