import AgentIDEDomain

public extension SessionService {
    /// Older findings can join a PR only while the captured code still matches.
    func restoreLocalReviewIdentity(
        worktreePath: String, repositoryPath: String, summary: PullRequestSummary,
    ) async -> Bool {
        guard let review = localReview(worktreePath: worktreePath), review.branch == nil,
              let revision = try? await localReviewRevision(worktreePath: worktreePath), revision == review.revision
        else {
            return false
        }

        let source = await localReviewSource(worktreePath: worktreePath)
        guard source.repository == repositoryPath, source.branch == summary.headBranch,
              summary.headRepository == nil || summary.headRepository == source.headRepository
        else {
            return false
        }

        var restored = false
        store.update { metadata in
            guard metadata.localReviews[worktreePath] == review else {
                return
            }

            metadata.localReviews[worktreePath]?.repositoryPath = repositoryPath
            metadata.localReviews[worktreePath]?.branch = summary.headBranch
            metadata.localReviews[worktreePath]?.pullRequestURL = summary.url
            metadata.localReviews[worktreePath]?.headRepository = source.headRepository
            restored = true
        }
        return restored
    }

    internal func localReviewSource(
        worktreePath: String,
    ) async -> LocalReviewSource {
        let repository = GitClient.owningCheckout(of: worktreePath) ?? worktreePath
        guard let branch = await git.currentBranch(worktreePath: worktreePath) else {
            return LocalReviewSource(repository: repository, branch: nil, url: nil, headRepository: nil)
        }

        let remote = await git.branchRemote(worktreePath: worktreePath, branch: branch) ?? "origin"
        let remoteURL = GitHubRemote.isURL(remote)
            ? remote : await git.remoteURL(named: remote, worktreePath: worktreePath)
        let headRepository = remoteURL.flatMap(GitHubRemote.fullName(ofURL:))
        let summaries = (pullRequests.cachedListing(repositoryPath: repository, scope: .branch(branch)) ?? [])
            .filter { $0.state == "OPEN" && ($0.headRepository == nil || $0.headRepository == headRepository) }
        return LocalReviewSource(
            repository: repository,
            branch: branch,
            url: summaries.count == 1 ? summaries.first?.url : nil,
            headRepository: headRepository,
        )
    }
}

// MARK: - LocalReviewSource

struct LocalReviewSource {
    let repository: String
    let branch: String?
    let url: String?
    let headRepository: String?
}
