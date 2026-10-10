import AgentIDEData
import AgentIDEDomain
import TerminalUI

extension PullRequestsModel {
    func localReview(for summary: PullRequestSummary) -> (path: String, review: LocalReview)? {
        let metadata = store.load()
        let state = metadata.pullRequestAutomation[PullRequestAutomation.key(for: summary.url)]
        let paths = metadata.localReviews.keys.sorted { left, right in
            if left == right {
                return false
            }
            if left == worktreePath {
                return true
            }
            if right == worktreePath {
                return false
            }
            return left < right
        }
        for path in paths {
            guard let review = metadata.localReviews[path], review.failure == nil else {
                continue
            }

            let recorded = review.repositoryPath == repository.path && review.branch == summary.headBranch
                && (review.pullRequestURL == nil || review.pullRequestURL == summary.url)
                && (summary.headRepository == nil || review.headRepository == summary.headRepository)
            let collected = state?.repositoryPath == repository.path && state?.number == summary.number
                && state?.feedbackWorktreePath == path && review.runID != nil
                && state?.collection?.review?.runID == review.runID
            if recorded || collected {
                return (path, review)
            }
        }
        return nil
    }

    func reviewCount(for summary: PullRequestSummary) -> Int {
        summary.unresolvedComments + (localReview(for: summary)?.review.remaining ?? 0)
    }

    func restoreLocalReview(for summary: PullRequestSummary) async {
        guard localReview(for: summary) == nil else {
            return
        }

        let candidates = items.filter { item in
            item.worktree.repositoryPath == repository.path && item.worktree.branch == summary.headBranch
        }
        for item in candidates where await restoreLocalReviewIdentity(item.worktree.path, summary) {
            UtilityTabTarget.pullRequestCacheChanged()
        }
    }

    func toggleLocalResolved(_ threadID: String, review: LocalReview, path: String) {
        store.update { metadata in
            guard var current = metadata.localReviews[path], current.runID == review.runID,
                  let index = current.threads.firstIndex(where: { $0.id == threadID })
            else {
                return
            }

            current.threads[index].isResolved.toggle()
            metadata.localReviews[path] = current
        }
        UtilityTabTarget.pullRequestCacheChanged()
    }
}
