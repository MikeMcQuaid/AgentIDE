import SanductorData

/// The single preparation and push action shared by the footer and shortcuts.
extension PullRequestsModel {
    /// Whether the entry in view is the repository's own default
    /// branch.
    var isDefaultBranch: Bool {
        listedBranch != nil && listedBranch == defaultBranch
    }

    /// Whether the entry in view is a default branch that refuses a
    /// push: one GitHub protects, or wants a pull request or passing
    /// checks on, which is most shared repositories. A repository of
    /// your own with none of that takes the push, and Push runs.
    var isGuardedDefaultBranch: Bool {
        isDefaultBranch && acceptsDefaultPushes == false
    }

    var canPublish: Bool {
        guard branchItem != nil, isBranchActionRunning == false, isGuardedDefaultBranch == false,
              queuedBranchBlocker == nil
        else {
            return false
        }

        if isInStack {
            return needsRestackBeforePush ? canRestack && unpushedBelow == nil : canPushStack
        }
        return canRebase || canPush || (tipSignature == .unsigned && hasUnpushedCommits)
    }

    var publishTitle: String {
        let behind = isInStack && mutableStackBranches != stack.branches ? 0 : branchItem?.behindDefault ?? 0
        let rebase = "Rebase" + (behind > 0 ? " ↓" + String(behind) : "") + " and Push"
        if isInStack {
            guard needsRestackBeforePush else {
                return "Push"
            }

            return needsStackRebase ? rebase : "Sign and Push"
        }
        guard rebaseNeed != .nothing || tipSignature == .unsigned else {
            return "Push"
        }

        return rebaseNeed == .sign || rebaseNeed == .nothing ? "Sign and Push" : rebase
    }

    var publishHelp: String {
        if let queuedBranchBlocker {
            return queuedBranchBlocker
        }
        if isInStack {
            if needsRestackBeforePush, canPublish {
                return "Rebase and sign as needed, then push the listed branch and published branches above it"
            }
            return stack.stackingBlocker ?? (needsRestackBeforePush ? restackBlocker : nil) ?? pushStackHelp
        }
        if isGuardedDefaultBranch || canRebase == false {
            return pushHelp
        }
        return rebaseTitle + ", then push this branch; a failure stops the sequence"
    }

    func publish() async -> Bool {
        guard isBranchActionRunning == false else {
            return true
        }

        if isGuardedDefaultBranch {
            return await push()
        }
        guard canPublish, let worktree = listedWorktree else {
            return true
        }

        isBranchActionRunning = true
        defer { isBranchActionRunning = false }
        if isInStack {
            return needsRestackBeforePush ? await restack() : await pushStack()
        }
        rebaseNeed = await fetchRebaseNeed(worktree)
        tipSignature = await checkTipSigned(worktree) ? .signed : .unsigned
        if rebaseNeed != .nothing || tipSignature == .unsigned {
            guard await rebaseSigned() else {
                return false
            }
        }
        return await push()
    }
}
