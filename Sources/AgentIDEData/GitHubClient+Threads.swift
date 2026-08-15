import AgentIDEDomain
import Foundation

/// The review conversation side of the client: fetching a pull
/// request's threads, toggling their resolve state and listing its
/// failing checks. Split from `GitHubClient.swift` for file length.
public extension GitHubClient {
    /// The REST inline comments, gh's HTTP cache answering repeats.
    private func restThreads(repositoryPath: String, number: Int) async -> [ReviewThread] {
        let result = try? await gh(
            ["api", "repos/{owner}/{repo}/pulls/\(number)/comments?per_page=100", "--cache", "60s"],
            in: repositoryPath,
        )
        return Self.threads(fromRESTJSON: result?.standardOutput ?? "")
    }

    /// Enough log to diagnose without flooding the clipboard.
    private static var runLogLimit: Int {
        // swiftlint:disable:next no_magic_numbers
        20_000
    }

    // MARK: Public

    /// The pull request's review conversation threads with a REST
    /// fallback: a failing GraphQL query must never make the
    /// conversation silently vanish. REST threads carry the anchor
    /// and comments but no resolvable id; throws only when GraphQL
    /// failed and REST answered nothing either.
    func conversationThreads(repositoryPath: String, number: Int) async throws -> [ReviewThread] {
        do {
            let threads = try await reviewThreads(repositoryPath: repositoryPath, number: number)
            if threads.isEmpty == false {
                return threads
            }
        } catch {
            let rest = await restThreads(repositoryPath: repositoryPath, number: number)
            guard rest.isEmpty == false else {
                throw error
            }

            return rest
        }
        return await restThreads(repositoryPath: repositoryPath, number: number)
    }

    /// The pull request's review conversation threads, each
    /// resolvable through its GraphQL id.
    func reviewThreads(repositoryPath: String, number: Int) async throws -> [ReviewThread] {
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
        let result = try await gh(
            [
                "api", "graphql",
                "-f", "query=" + query,
                "-f", "owner=" + String(owner),
                "-f", "name=" + String(name),
                "-F", "number=" + String(number),
            ],
            in: repositoryPath,
        )
        return Self.threads(fromJSON: result.standardOutput)
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

    /// Groups the REST inline comments into anchored threads; the
    /// REST rows carry no resolvable thread id, so these render
    /// without a resolve button.
    internal static func threads(fromRESTJSON json: String) -> [ReviewThread] {
        let decoded = try? JSONDecoder().decode([RESTInlineComment].self, from: Data(json.utf8))
        var roots = [Int]()
        var commentsByRoot = [Int: [ReviewThreadComment]]()
        var anchorsByRoot = [Int: (path: String, line: Int?)]()
        for row in decoded ?? [] {
            let root = row.inReplyToID ?? row.id
            if commentsByRoot[root] == nil {
                roots.append(root)
                anchorsByRoot[root] = (row.path ?? "", row.line ?? row.originalLine)
            }
            commentsByRoot[root, default: []].append(
                ReviewThreadComment(author: row.user?.login ?? "unknown", body: row.body ?? ""),
            )
        }
        return roots.map { root in
            ReviewThread(
                id: "rest-" + String(root),
                path: anchorsByRoot[root]?.path ?? "",
                line: anchorsByRoot[root]?.line,
                isResolved: false,
                comments: commentsByRoot[root] ?? [],
                resolveID: "",
            )
        }
    }

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
        return nodes.compactMap { node in
            guard let node else {
                return nil
            }

            return ReviewThread(
                id: node.id,
                path: node.path,
                line: node.line,
                isResolved: node.isResolved,
                comments: node.comments.nodes.compactMap { comment in
                    comment.map { ReviewThreadComment(author: $0.author?.login ?? "unknown", body: $0.body) }
                },
            )
        }
    }
}

// MARK: - RESTInlineComment

/// One REST inline review comment; replies name their root through
/// `in_reply_to_id`.
private struct RESTInlineComment: Decodable {
    // MARK: Internal

    struct Author: Decodable {
        let login: String
    }

    let id: Int
    let path: String?
    let line: Int?
    let originalLine: Int?
    let inReplyToID: Int?
    let body: String?
    let user: Author?

    // MARK: Private

    // swiftlint:disable explicit_enum_raw_value
    private enum CodingKeys: String, CodingKey {
        case id
        case path
        case line
        case originalLine = "original_line"
        case inReplyToID = "in_reply_to_id"
        case body
        case user
    }

    // swiftlint:enable explicit_enum_raw_value
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
        /// Element-nullable in the schema; one null must not drop
        /// every thread.
        let nodes: [CommentNode?]
    }

    struct ThreadNode: Decodable {
        let id: String
        let isResolved: Bool
        let path: String
        let line: Int?
        let comments: CommentNodes
    }

    struct ThreadNodes: Decodable {
        /// Element-nullable in the schema; one null must not drop
        /// every thread.
        let nodes: [ThreadNode?]
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
