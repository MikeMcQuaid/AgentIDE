import AgentIDEData
import AgentIDEDomain

/// Which branch the tab acts on and whether it can: an entry of a
/// stack is read without being checked out, so what a button reads
/// and what it moves are not always the branch the worktree holds.
/// Split from the actions for length.
extension PullRequestsModel {
    /// The rebase button's label names exactly what it would do.
    var rebaseTitle: String {
        guard AppSettings.requiresSignedCommits else {
            return "Rebase on origin"
        }

        return switch rebaseNeed {
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
    /// something: move the base, sign commits, or both. It acts on
    /// the entry in view, checking it out for the rebase and putting
    /// the worktree back: an entry whose tip is unsigned could
    /// otherwise never be pushed, since Push waits for the signature
    /// only this can give it.
    var canRebase: Bool {
        branchItem != nil && rebaseNeed != SessionService.RebaseNeed.nothing
    }

    func rebaseSigned() async -> Bool {
        guard let worktree = listedWorktree else {
            return true
        }

        isBranchActionRunning = true
        defer { isBranchActionRunning = false }
        do {
            try await performRebase(worktree)
            // A stack member that moves takes the branches above it
            // with it. Left where they were, they fork from the
            // default branch instead of from it, which is not a
            // stack at all: the tab lost the entry that had just
            // moved and showed whichever branch was checked out, so
            // the next press rebased that one instead.
            if stacking.stack.isStacked {
                do {
                    _ = try await stacking.restack(worktree)
                } catch {
                    report("Rebasing the branches above " + worktree.branch + " failed: "
                        + error.localizedDescription)
                }
            }
            await reload(keepingSelection: true)
            // Done means Push agrees; reporting success with the tip
            // still unsigned took a second press to notice.
            if isTipSigned == false {
                report("Rebased, but the tip still reads unsigned; check the signing key "
                    + "and hit Rebase again")
                return false
            }
            setStatus("Rebased and signed.", detail: "Rebased and signed " + worktree.branch + ".")
            Self.requestSidebarRefresh()
            return true
        } catch {
            report(error.localizedDescription)
            return false
        }
    }

    /// The one merge action's label, naming exactly what a click
    /// does right now; nil when no open conversation is selected.
    var mergeActionTitle: String? {
        guard let selected, selected.state == "OPEN" else {
            return nil
        }

        if selected.hasAutomerge {
            return hasMergeQueue ? "Dequeue" : "Cancel automerge"
        }
        if selected.checks == "SUCCESS", selected.mergeable == "MERGEABLE" {
            return hasMergeQueue ? "Queue" : "Merge"
        }
        return "Automerge"
    }

    /// The present-tense form while the merge action runs.
    var mergeActionBusyTitle: String {
        switch mergeActionTitle {
        case "Dequeue":
            "Dequeuing"

        case "Cancel automerge":
            "Cancelling"

        case "Queue":
            "Queueing"

        case "Merge":
            "Merging"

        default:
            "Enabling automerge"
        }
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

    /// Whether one pull request could be merged as it stands: no
    /// draft, no conflict, checks green, and no review outstanding
    /// or refused. An empty review decision is a repository that
    /// asks for none.
    static func isReadyToMerge(_ summary: PullRequestSummary) -> Bool {
        summary.state == "OPEN" && summary.isDraft == false
            && summary.mergeable == "MERGEABLE" && summary.checks == "SUCCESS"
            && ["", "APPROVED"].contains(summary.reviewDecision)
    }
}
