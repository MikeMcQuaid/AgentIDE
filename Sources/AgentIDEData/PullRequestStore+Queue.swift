import AgentIDEDomain

public extension PullRequestStore {
    /// Maps the shared queue membership to branch names without another read.
    func cachedQueuedBranches(repositoryPath: String) -> Set<String> {
        let numbers = store.load().queuedCache[repositoryPath].map(Set.init)
        return Set(cachedQueueSummaries(repositoryPath: repositoryPath)
            .filter { numbers?.contains($0.number) ?? ($0.isQueued && $0.state == "OPEN") }
            .map(\.headBranch))
    }

    /// Refreshes membership and fills missing identities before changing branches.
    func queuedBranches(repositoryPath: String) async throws -> Set<String> {
        store.update { $0.fetchedAt["queue#" + repositoryPath] = nil }
        _ = await queuedNumbers(repositoryPaths: [repositoryPath])
        let cached = cachedQueueSummaries(repositoryPath: repositoryPath)
        let numbers = store.load().queuedCache[repositoryPath].map(Set.init)
            ?? Set(cached.filter { $0.isQueued && $0.state == "OPEN" }.map(\.number))
        let known = cached.filter { $0.headBranch.isEmpty == false }
        var branches = Set(known.filter { numbers.contains($0.number) }.map(\.headBranch))
        for number in numbers.subtracting(known.map(\.number)) {
            store.update { $0.fetchedAt[Self.summaryKey(repositoryPath: repositoryPath, number: number)] = nil }
            guard let summary = try await summary(repositoryPath: repositoryPath, number: number),
                  summary.number == number, summary.headBranch.isEmpty == false
            else {
                throw SessionServiceError("Cannot identify the branch for queued pull request #" + String(number)
                    + ". Refresh before rebasing, signing or pushing.")
            }

            branches.insert(summary.headBranch)
        }
        return branches
    }

    internal func cachedQueueSummaries(repositoryPath: String) -> [PullRequestSummary] {
        let metadata = store.load()
        return metadata.pullRequestCache.filter { $0.key.hasPrefix(repositoryPath + "#") }.map(\.value)
            + metadata.enrichedSummaryCache
            .filter { $0.key.hasPrefix("summary#" + repositoryPath + "#") }
            .map(\.value.summary)
            + metadata.pullRequestListsCache
            .filter { $0.key.hasPrefix("list#" + repositoryPath + "#") }
            .flatMap(\.value.summaries)
    }
}
