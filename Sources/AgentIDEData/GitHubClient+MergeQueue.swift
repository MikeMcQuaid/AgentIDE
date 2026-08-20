import Foundation

/// The merge queue, which only the queue itself can answer: no `gh
/// pr` field reports membership. `isInMergeQueue` does not exist and
/// `mergeStateStatus` has no queued state, so both questions here go
/// to GraphQL, and a failure answers "not queued" rather than taking
/// a pull request listing down with it.
public extension GitHubClient {
    /// Whether the repository merges through a merge queue, so merge
    /// controls can say queue rather than merge.
    func hasMergeQueue(repositoryPath: String) async -> Bool {
        let query = "query($owner: String!, $name: String!) "
            + "{ repository(owner: $owner, name: $name) { mergeQueue { id } } }"
        // A repository setting that rarely changes; gh's HTTP cache
        // answers repeats for a day.
        let result = await graphQL(query, repositoryPath: repositoryPath, cache: "24h")
        return result?.contains("\"mergeQueue\":{") ?? false
    }

    /// The pull requests actually in the repository's merge queue.
    /// One query names every entry, which is far cheaper than asking
    /// per pull request, and lets the sidebar mark the queued ones.
    func queuedNumbers(repositoryPath: String) async -> Set<Int> {
        let query = "query($owner: String!, $name: String!) { repository(owner: $owner, name: $name) "
            + "{ mergeQueue { entries(first: 100) { nodes { pullRequest { number } } } } } }"
        let result = await graphQL(query, repositoryPath: repositoryPath, cache: nil)
        return Self.queuedNumbers(fromJSON: result ?? "")
    }
}

extension GitHubClient {
    /// The numbers in a merge queue entries answer; an answer that
    /// does not parse means nothing queued, which is what a
    /// repository without a queue reports anyway.
    static func queuedNumbers(fromJSON json: String) -> Set<Int> {
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(MergeQueueResponse.self, from: data)
        else {
            return []
        }

        let nodes = decoded.data?.repository?.mergeQueue?.entries?.nodes ?? []
        return Set(nodes.compactMap(\.pullRequest?.number))
    }

    /// Runs a repository-scoped query, which every caller here is,
    /// against the origin's owner and name.
    private func graphQL(_ query: String, repositoryPath: String, cache: String?) async -> String? {
        let parts = await (fullName(repositoryPath: repositoryPath) ?? "").split(separator: "/", maxSplits: 1)
        guard let owner = parts.first, let name = parts.dropFirst().first else {
            return nil
        }

        let caching = cache.map { ["--cache", $0] } ?? []
        let result = try? await gh(
            ["api", "graphql"] + caching + [
                "-f", "query=" + query,
                "-f", "owner=" + String(owner),
                "-f", "name=" + String(name),
            ],
            in: repositoryPath,
            allowFailure: true,
        )
        return result?.standardOutput
    }
}

// MARK: - MergeQueueResponse

/// `repository { mergeQueue { entries { nodes { pullRequest }}}}` as
/// GraphQL answers it, every level optional: a repository with no
/// queue answers null the whole way down.
private struct MergeQueueResponse: Decodable {
    let data: ResponseData?
}

// MARK: - ResponseData

private struct ResponseData: Decodable {
    let repository: QueueRepository?
}

// MARK: - QueueRepository

private struct QueueRepository: Decodable {
    let mergeQueue: MergeQueue?
}

// MARK: - MergeQueue

private struct MergeQueue: Decodable {
    let entries: QueueEntries?
}

// MARK: - QueueEntries

private struct QueueEntries: Decodable {
    /// Not optional: an answer missing its nodes fails to decode,
    /// which reads as nothing queued, exactly as null nodes would.
    let nodes: [QueueNode]
}

// MARK: - QueueNode

private struct QueueNode: Decodable {
    let pullRequest: QueuedPullRequest?
}

// MARK: - QueuedPullRequest

private struct QueuedPullRequest: Decodable {
    let number: Int
}
