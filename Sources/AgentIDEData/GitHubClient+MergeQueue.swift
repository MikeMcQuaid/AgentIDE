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

    /// Every repository's merge queue in one query, each repository
    /// an alias: the sidebar asks about all of them at once every
    /// minute, and one round trip is what that should cost rather
    /// than one per repository.
    func queuedNumbers(repositoryPaths: [String]) async -> [String: Set<Int>] {
        var aliases = [(alias: String, path: String)]()
        var fields = [String]()
        for (index, path) in repositoryPaths.enumerated() {
            let parts = await (fullName(repositoryPath: path) ?? "").split(separator: "/", maxSplits: 1)
            guard let owner = parts.first, let name = parts.dropFirst().first else {
                continue
            }

            let alias = "r" + String(index)
            aliases.append((alias, path))
            fields.append(alias + ": repository(owner: \"" + owner + "\", name: \"" + name + "\") "
                + "{ mergeQueue { entries(first: 100) { nodes { pullRequest { number } } } } }")
        }
        guard fields.isEmpty == false, let directory = aliases.first?.path else {
            return [:]
        }

        let query = "query { " + fields.joined(separator: " ") + " }"
        let result = try? await gh(["api", "graphql", "-f", "query=" + query], in: directory, allowFailure: true)
        let byAlias = Self.queuedNumbers(fromAliasedJSON: result?.standardOutput ?? "")
        var queued = [String: Set<Int>]()
        for (alias, path) in aliases {
            queued[path] = byAlias[alias] ?? []
        }
        return queued
    }
}

extension GitHubClient {
    /// The queued numbers under each alias of an answer; a plain
    /// answer's one repository is under `repository`.
    static func queuedNumbers(fromAliasedJSON json: String) -> [String: Set<Int>] {
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(MergeQueueResponse.self, from: data)
        else {
            return [:]
        }

        return decoded.data.mapValues { repository in
            Set((repository?.mergeQueue?.entries?.nodes ?? []).compactMap(\.pullRequest?.number))
        }
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
    // MARK: Lifecycle

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decodeIfPresent([String: QueueRepository?].self, forKey: .data) ?? [:]
    }

    // MARK: Internal

    /// Every top-level field is a repository under its alias; a
    /// repository the token cannot see decodes as null, and an
    /// answer with no data at all as no repositories.
    let data: [String: QueueRepository?]

    // MARK: Private

    private enum CodingKeys: CodingKey {
        case data
    }
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
