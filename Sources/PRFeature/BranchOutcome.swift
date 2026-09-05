// MARK: - BranchOutcome

/// What a branch action leaves behind, which its own button says in
/// the past tense while it stays dim: the footer used to say it in
/// the middle of the bar, away from the button that did the work.
enum BranchOutcome: Equatable {
    case rebased
    case signed
    case pushed
}

extension PullRequestsModel {
    /// What the last read said of the tip commit's signature:
    /// unread until the current tip has been checked. Pushing
    /// unsigned commits is never allowed, so Push waits for proof
    /// rather than trusting a stale answer, and dims until Rebase
    /// on origin signs the branch.
    enum TipSignature {
        case unread
        case unsigned
        case signed
    }

    /// The branch every past tense is about: the entry being listed
    /// rather than whatever the worktree holds, so reading up and
    /// down a stack never shows one branch's work on another's.
    var actedBranch: String? {
        listedBranch
    }

    /// What the rebase button says once it has nothing left to do
    /// because it has just done it; nil when it has not.
    var rebaseDoneTitle: String? {
        guard let finished, finished.branch == actedBranch else {
            return nil
        }

        return switch finished.outcome {
        case .rebased:
            "Rebased"

        case .signed:
            "Signed"

        case .pushed:
            nil
        }
    }

    /// The same for the push button.
    var pushDoneTitle: String? {
        guard let finished, finished.branch == actedBranch, finished.outcome == .pushed else {
            return nil
        }

        return "Pushed"
    }

    /// Records what an action finished, for the button that did it.
    /// The line in the middle of the bar is for what went wrong, so
    /// a success clears whatever refusal is still standing there.
    func recordFinished(_ outcome: BranchOutcome, branch: String) {
        finished = (outcome, branch)
        status = nil
    }
}
