import AgentIDEData
import AgentIDEDomain

/// Which branch the tab acts on and whether it can: an entry of a
/// stack is read without being checked out, so what a button reads
/// and what it moves are not always the branch the worktree holds.
/// Split from the actions for length.
extension PullRequestsModel {
    /// The rebase button's label names exactly what it would do.
    var rebaseTitle: String {
        switch rebaseNeed {
        case .sign:
            "Sign commits"

        case .rebaseAndSign:
            "Rebase and sign"

        case .nothing,
             .rebase:
            "Rebase on origin"
        }
    }

    /// Rebase only lights up when it would actually change
    /// something: move the base, sign commits, or both. A rebase
    /// moves the branch the worktree holds, so an entry being read
    /// without being checked out is not its to move.
    var canRebase: Bool {
        branchItem != nil && rebaseNeed != SessionService.RebaseNeed.nothing && isListedCheckedOut
    }

    /// Whether the entry on screen is the branch the worktree
    /// actually holds, which is always so outside a stack. The
    /// stack's own checked-out name counts too: where a local-only
    /// twin is checked out, the entry standing for it is at the same
    /// commit, so rebasing and pushing are still its work.
    var isListedCheckedOut: Bool {
        listedBranch == (currentBranch ?? branch) || listedBranch == stacking.stack.checkedOut
    }

    /// Push makes sense with unpushed commits that this tab has not
    /// already pushed and a GPG-signed tip; nil upstream means
    /// nothing was ever pushed. In a stack it is the listed entry's
    /// own commits that are counted, since the worktree's counts
    /// describe whichever branch it has checked out.
    var canPush: Bool {
        guard branchItem != nil, isPushed == false, isTipSigned else {
            return false
        }

        return hasUnpushedCommits
    }

    /// Whether the listed branch has commits the remote lacks: the
    /// stack's own reading when there is one, the worktree's
    /// upstream count otherwise.
    var hasUnpushedCommits: Bool {
        guard stacking.stack.isStacked, let listed = listedBranch else {
            return (branchItem?.aheadOfUpstream ?? 1) > 0
        }

        return stacking.unpushedBranches.contains(listed)
    }

    /// Why Push is in its current state, for the button's hover:
    /// with nothing to push that is the whole story, and signing
    /// only matters once commits are waiting.
    var pushHelp: String {
        guard branchItem != nil, isPushed == false, hasUnpushedCommits else {
            return "Everything is already pushed"
        }
        guard isTipSigned else {
            return "The tip commit is not GPG signed; Rebase on origin signs the branch first"
        }

        return "Push this branch's unpushed commits to origin; a failure reports to the Errors tab"
    }

    /// The branch item's worktree with the checked-out branch
    /// substituted, so pushes and rebases act on what is actually
    /// checked out.
    var actionWorktree: Worktree? {
        worktree(on: currentBranch)
    }

    /// The same worktree with the listed entry's branch: a pull
    /// request is opened for the branch whose form was filled in,
    /// which in a stack need not be the one checked out.
    var listedWorktree: Worktree? {
        worktree(on: listedBranch)
    }

    /// The branch item's worktree as it stands on another of its
    /// branches; every entry of a stack is the same directory.
    func worktree(on branch: String?) -> Worktree? {
        guard let item = branchItem else {
            return nil
        }
        guard let branch, branch != item.worktree.branch else {
            return item.worktree
        }

        return Worktree(
            repositoryName: item.worktree.repositoryName,
            repositoryPath: item.worktree.repositoryPath,
            branch: branch,
            path: item.worktree.path,
        )
    }
}
