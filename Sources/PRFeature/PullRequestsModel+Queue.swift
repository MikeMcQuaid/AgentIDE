/// Queue membership can change without any git ref moving.
extension PullRequestsModel {
    var mutableStackBranches: [String] {
        stack.mutableBranches(queued: pullRequests.cachedQueuedBranches(repositoryPath: repository.path))
    }

    var needsStackRebase: Bool {
        mutableStackBranches.contains(where: stacking.outOfPlaceBranches.contains)
    }

    var unsignedStackBranches: [String] {
        mutableStackBranches.filter(stacking.unsignedBranches.contains)
    }

    var queuedBranchBlocker: String? {
        guard let listedBranch else {
            return nil
        }

        let queued = pullRequests.cachedQueuedBranches(repositoryPath: repository.path)
        let fixed = stack.branches.contains(listedBranch) && mutableStackBranches.contains(listedBranch) == false
        guard queued.contains(listedBranch) || fixed
        else {
            return nil
        }

        return "This branch is queued or below queued work; wait for it to merge or dequeue it"
    }
}
