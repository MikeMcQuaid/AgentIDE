import AgentIDEDomain
import Foundation

/// The review conversation side of the client: fetching a pull
/// request's threads, toggling their resolve state and listing its
/// failing checks. Split from `GitHubClient.swift` for file length.
public extension GitHubClient {
    /// Enough log to diagnose without flooding the clipboard.
    private static var runLogLimit: Int {
        // swiftlint:disable:next no_magic_numbers
        20_000
    }

    // MARK: Public

    /// The pull request's review conversation threads, each
    /// resolvable through its GraphQL id.
    func reviewThreads(repositoryPath: String, number: Int) async -> [ReviewThread] {
        guard let fullName = await fullName(repositoryPath: repositoryPath) else {
            return []
        }

        let parts = fullName.split(separator: "/", maxSplits: 1)
        guard let owner = parts.first, let name = parts.dropFirst().first else {
            return []
        }

        let query = "query($owner: String!, $name: String!, $number: Int!) "
            + "{ repository(owner: $owner, name: $name) { pullRequest(number: $number) "
            + "{ reviewThreads(first: 100) { nodes { id isResolved path line "
            + "comments(first: 50) { nodes { author { login } body } } } } } } }"
        let result = try? await gh(
            [
                "api", "graphql",
                "-f", "query=" + query,
                "-f", "owner=" + String(owner),
                "-f", "name=" + String(name),
                "-F", "number=" + String(number),
            ],
            in: repositoryPath,
        )
        return Self.threads(fromJSON: result?.standardOutput ?? "")
    }

    /// Marks one review thread resolved or unresolved.
    func setThreadResolved(repositoryPath: String, threadID: String, resolved: Bool) async throws {
        let mutation = resolved
            ? "mutation($id: ID!) { resolveReviewThread(input: { threadId: $id }) { thread { id } } }"
            : "mutation($id: ID!) { unresolveReviewThread(input: { threadId: $id }) { thread { id } } }"
        try await gh(
            ["api", "graphql", "-f", "query=" + mutation, "-f", "id=" + threadID],
            in: repositoryPath,
        )
    }

    /// The pull request's failing checks, one line each, followed by
    /// each failing Actions run's failed step output; the links
    /// alone were useless for pasting into an agent. Passing,
    /// pending and skipped rows are noise for every caller.
    func failingChecks(repositoryPath: String, number: Int) async -> String {
        let checks = try? await gh(
            ["pr", "checks", String(number)],
            in: repositoryPath,
            allowFailure: true,
        )
        let failing = (checks?.standardOutput ?? "")
            .split(separator: "\n")
            .filter { line in
                let fields = line.split(separator: "\t")
                return fields.count > 1 && fields[1].localizedCaseInsensitiveContains("fail")
            }
            .map(String.init)
        var sections = failing.joined(separator: "\n")
        for runID in Self.runIDs(fromCheckLines: failing) {
            let log = try? await gh(
                ["run", "view", runID, "--log-failed"],
                in: repositoryPath,
                allowFailure: true,
            )
            let output = (log?.standardOutput ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard output.isEmpty == false else {
                continue
            }

            sections += "\n\nFailed steps of run " + runID + ":\n" + String(output.prefix(Self.runLogLimit))
        }
        return sections
    }

    // MARK: Internal

    /// Distinct Actions run ids from the failing check lines'
    /// links, in order; external checks without an Actions link
    /// contribute no logs.
    internal static func runIDs(fromCheckLines lines: [String]) -> [String] {
        var ids = [String]()
        for line in lines {
            guard let range = line.range(of: "/actions/runs/") else {
                continue
            }

            let id = String(line[range.upperBound...].prefix(while: \.isNumber))
            if id.isEmpty == false, ids.contains(id) == false {
                ids.append(id)
            }
        }
        return ids
    }

    /// Decodes the reviewThreads GraphQL answer.
    internal static func threads(fromJSON json: String) -> [ReviewThread] {
        let decoded = try? JSONDecoder().decode(ThreadsResponse.self, from: Data(json.utf8))
        let nodes = decoded?.data?.repository?.pullRequest?.reviewThreads.nodes ?? []
        return nodes.map { node in
            ReviewThread(
                id: node.id,
                path: node.path,
                line: node.line,
                isResolved: node.isResolved,
                comments: node.comments.nodes.map { comment in
                    ReviewThreadComment(author: comment.author?.login ?? "unknown", body: comment.body)
                },
            )
        }
    }
}

// MARK: - ThreadsResponse

/// The reviewThreads GraphQL answer's shape. Fields the schema
/// declares non-null are non-optional; a null pull request (wrong
/// number) or missing data decodes to an empty listing.
private struct ThreadsResponse: Decodable {
    struct Author: Decodable {
        let login: String
    }

    struct CommentNode: Decodable {
        /// Null when the commenting account was deleted.
        let author: Author?
        let body: String
    }

    struct CommentNodes: Decodable {
        let nodes: [CommentNode]
    }

    struct ThreadNode: Decodable {
        let id: String
        let isResolved: Bool
        let path: String
        let line: Int?
        let comments: CommentNodes
    }

    struct ThreadNodes: Decodable {
        let nodes: [ThreadNode]
    }

    struct PullRequest: Decodable {
        let reviewThreads: ThreadNodes
    }

    struct Repo: Decodable {
        let pullRequest: PullRequest?
    }

    struct DataBox: Decodable {
        let repository: Repo?
    }

    let data: DataBox?
}
