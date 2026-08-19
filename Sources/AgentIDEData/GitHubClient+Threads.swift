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

    // MARK: Public

    /// The pull request's review conversation threads with a REST
    /// fallback: a failing GraphQL query must never make the
    /// conversation silently vanish, but the failure still names
    /// itself, because REST threads carry no resolvable id and the
    /// missing resolve buttons otherwise look like a display bug.
    func conversationThreads(repositoryPath: String, number: Int) async -> ConversationThreads {
        do {
            let threads = try await reviewThreads(repositoryPath: repositoryPath, number: number)
            if threads.isEmpty == false {
                return ConversationThreads(threads: threads, graphQLFailure: nil)
            }

            return await ConversationThreads(
                threads: restThreads(repositoryPath: repositoryPath, number: number),
                graphQLFailure: nil,
            )
        } catch {
            return await ConversationThreads(
                threads: restThreads(repositoryPath: repositoryPath, number: number),
                graphQLFailure: error.localizedDescription,
            )
        }
    }

    /// The pull request's review conversation threads, each
    /// resolvable through its GraphQL id.
    func reviewThreads(repositoryPath: String, number: Int) async throws -> [ReviewThread] {
        // Loud guards: an early silent return here used to read as
        // an empty conversation and hide the real fault.
        guard let fullName = await fullName(repositoryPath: repositoryPath) else {
            throw ThreadDecodeError(message: "the repository's GitHub name is unknown; is origin set?")
        }

        let parts = fullName.split(separator: "/", maxSplits: 1)
        guard let owner = parts.first, let name = parts.dropFirst().first else {
            throw ThreadDecodeError(message: "unexpected repository name shape: " + fullName)
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
        return try Self.threads(fromJSON: result.standardOutput)
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

    /// Decodes the reviewThreads GraphQL answer; a decode failure
    /// names the mismatching field, the only way shape drift in the
    /// live answer ever gets diagnosed.
    internal static func threads(fromJSON json: String) throws -> [ReviewThread] {
        let decoded: ThreadsResponse
        do {
            decoded = try JSONDecoder().decode(ThreadsResponse.self, from: Data(json.utf8))
        } catch {
            throw ThreadDecodeError(
                message: "reviewThreads answer did not decode: "
                    + String(String(describing: error).prefix(ThreadDecodeError.detailLimit)),
            )
        }
        guard let data = decoded.data else {
            throw ThreadDecodeError(message: "the reviewThreads answer carried no data")
        }

        let nodes = data.repository?.pullRequest?.reviewThreads.nodes ?? []
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

// MARK: - ConversationThreads

/// A conversation listing and, when the REST fallback rescued it,
/// the GraphQL failure the caller should surface.
public struct ConversationThreads: Sendable {
    /// The threads to render, whichever source answered.
    public let threads: [ReviewThread]

    /// Why GraphQL failed, nil when it answered; without it the
    /// missing resolve buttons look like a display bug.
    public let graphQLFailure: String?
}

// MARK: - ThreadDecodeError

/// A reviewThreads decode failure, carrying the mismatch detail.
struct ThreadDecodeError: LocalizedError {
    /// Enough decoder detail to name the field without flooding.
    static let detailLimit = 300

    let message: String

    var errorDescription: String? {
        message
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
