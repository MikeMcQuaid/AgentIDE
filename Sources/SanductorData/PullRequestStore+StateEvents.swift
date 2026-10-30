import SanductorDomain

extension PullRequestStore {
    /// Event history changes only when the PR or its queue membership
    /// does, and its timestamp outlives the view and app.
    func withStateChange(
        _ summary: PullRequestSummary,
        previous: PullRequestSummary?,
        repositoryPath: String,
    ) async -> PullRequestSummary {
        var dated = summary
        dated.isQueued = summary.state == "OPEN"
            && (store.load().queuedCache[repositoryPath]?.contains(summary.number) ?? summary.isQueued)
        guard summary.state == "OPEN", summary.updatedAt != nil else {
            return dated
        }

        if let previous, previous.updatedAt == summary.updatedAt,
           previous.state == summary.state, previous.isDraft == summary.isDraft,
           previous.isQueued == dated.isQueued, previous.stateChangedAt != nil
        {
            dated.stateChangedAt = previous.stateChangedAt
        } else {
            dated.stateChangedAt = try? await github.stateChangedAt(
                repositoryPath: repositoryPath, number: summary.number,
            )
        }
        return dated
    }
}
