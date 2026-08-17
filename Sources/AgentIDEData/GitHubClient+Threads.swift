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

    /// `gh run view --log-failed` prefixes every line with its job
    /// and step names, tab separated.
    private static var stepPrefixFields: Int {
        // swiftlint:disable:next no_magic_numbers
        2
    }

    /// How many lines of a failed step to keep, and how many before
    /// its first error line for context.
    private static var stepTailLines: Int {
        // swiftlint:disable:next no_magic_numbers
        60
    }

    private static var errorContextLines: Int {
        // swiftlint:disable:next no_magic_numbers
        5
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

            sections += "\n\nFailed steps of run " + runID + ":\n" + Self.failureExcerpt(fromRunLog: output)
        }
        return sections
    }

    // MARK: Internal

    /// The useful part of a `gh run view --log-failed` dump: its
    /// lines carry a repeated `job\tstep\t` prefix, and the failure
    /// is at the end, so the head of a long log was setup noise
    /// rather than the error. Each failed step keeps its own tail,
    /// from its first error line where one exists.
    internal static func failureExcerpt(fromRunLog log: String) -> String {
        var steps = [String]()
        var lines = [String: [String]]()
        for raw in log.split(separator: "\n", omittingEmptySubsequences: false) {
            let fields = raw.split(separator: "\t", maxSplits: stepPrefixFields, omittingEmptySubsequences: false)
            let step = fields.count > stepPrefixFields
                ? fields[0 ..< stepPrefixFields].joined(separator: " / ")
                : ""
            let text = fields.count > stepPrefixFields ? String(fields[stepPrefixFields]) : String(raw)
            if lines[step] == nil {
                steps.append(step)
                lines[step] = []
            }
            lines[step]?.append(text)
        }
        return steps
            .map { step in
                let body = Self.tail(of: lines[step] ?? [])
                return step.isEmpty ? body : step + "\n" + body
            }
            .joined(separator: "\n\n")
            .prefixWithinLimit(runLogLimit)
    }

    /// One step's last lines, starting at its first error line when
    /// it has one: the message that explains the failure sits there,
    /// with the lines after it as context.
    internal static func tail(of lines: [String]) -> String {
        let markers = ["error:", "##[error]", "error ", "failed", "fatal:", "assertion"]
        let firstError = lines.firstIndex { line in
            let lowered = line.lowercased()
            return markers.contains { lowered.contains($0) }
        }
        let start = firstError.map { max($0 - errorContextLines, 0) }
            ?? max(lines.count - stepTailLines, 0)
        return lines[start...].suffix(stepTailLines).joined(separator: "\n")
    }

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
