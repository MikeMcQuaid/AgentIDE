import AgentIDEDomain
import Foundation

// MARK: - ConditionalAnswer

/// What a conditional request came back with: the same thing as
/// last time, which GitHub answers with a 304 and does not count
/// against the rate limit, or a new body with the tag to send next
/// time.
public enum ConditionalAnswer: Sendable {
    case unchanged
    case changed(body: String, etag: String?)
}

/// Conditional REST requests through `gh api`: the entity tag of the
/// last answer travels back as `If-None-Match`, so a poll that finds
/// nothing changed costs one round trip and no rate limit. GraphQL
/// has no entity tags, which is why the branch listing the sidebar
/// asks for most often moved to REST.
public extension GitHubClient {
    /// Asks a REST path, sending the last entity tag when there is
    /// one. `gh api --include` puts the status line and headers
    /// before the body; a 304 has no body at all.
    func conditionalGet(path: String, etag: String?, repositoryPath: String) async throws -> ConditionalAnswer {
        var arguments = ["api", "--include"]
        if let etag {
            arguments += ["--header", "If-None-Match: " + etag]
        }
        arguments.append(path)
        // A 304 makes gh exit non-zero; that is the answer, not a
        // failure.
        let result = try await gh(arguments, in: repositoryPath, allowFailure: true)
        let output = result.standardOutput
        guard let statusLine = output.split(separator: "\n", maxSplits: 1).first else {
            throw CommandError(command: "gh api " + path, result: result)
        }

        if statusLine.contains(" 304") {
            return .unchanged
        }
        guard result.succeeded else {
            throw CommandError(command: "gh api " + path, result: result)
        }

        let (headers, body) = Self.splitHeaders(output)
        let tag = headers.first { $0.lowercased().hasPrefix("etag:") }
            .map { String($0.dropFirst("etag:".count)).trimmingCharacters(in: .whitespaces) }
        return .changed(body: body, etag: tag)
    }

    /// The pull requests from one branch through REST, light fields
    /// only, which is what the sidebar's rows show: the checks,
    /// mergeability and review decision are asked of one pull request
    /// on selection, as they always were.
    func branchPullRequests(
        repositoryPath: String,
        branch: String,
        etag: String?,
    ) async throws -> ConditionalAnswer {
        guard let fullName = await fullName(repositoryPath: repositoryPath) else {
            throw CommandError(
                command: "pulls for " + branch,
                result: ProcessResult(status: 1, standardOutput: "", standardError: "No GitHub remote"),
            )
        }

        let owner = fullName.split(separator: "/").first.map(String.init) ?? ""
        let path = "repos/" + fullName + "/pulls?state=all&per_page=" + String(Self.listLimit)
            + "&head=" + owner + ":" + branch
        return try await conditionalGet(path: path, etag: etag, repositoryPath: repositoryPath)
    }

    /// Parses REST `pulls` rows into summaries; separated for tests.
    static func summaries(fromRESTJSON json: String) -> [PullRequestSummary] {
        guard let data = json.data(using: .utf8) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // REST speaks snake case; the rows are named the Swift way.
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let rows = (try? decoder.decode([RESTPullRow].self, from: data)) ?? []
        return rows.map { row in
            PullRequestSummary(
                number: row.number,
                title: row.title,
                // swiftformat:disable:next acronyms
                url: row.htmlUrl,
                headBranch: row.head.ref,
                mergeable: "",
                reviewDecision: "",
                checks: "",
                baseBranch: row.base.ref,
                state: row.mergedAt != nil ? "MERGED" : row.state.uppercased(),
                isDraft: row.draft ?? false,
                hasAutomerge: row.autoMerge != nil,
                author: row.user?.login,
                body: row.body,
                closedAt: row.closedAt,
            )
        }
    }

    // MARK: Internal

    /// The headers and body of a `--include` answer, split at the
    /// first blank line.
    internal static func splitHeaders(_ output: String) -> (headers: [String], body: String) {
        guard let blank = output.range(of: "\r\n\r\n") ?? output.range(of: "\n\n") else {
            return ([], output)
        }

        let headers = output[..<blank.lowerBound].split(whereSeparator: \.isNewline).map(String.init)
        return (headers, String(output[blank.upperBound...]))
    }
}

// MARK: - RESTPullRow

private struct RESTPullRow: Decodable {
    struct Ref: Decodable {
        let ref: String
    }

    struct User: Decodable {
        let login: String?
    }

    struct AutoMerge: Decodable {
        // Presence is the signal.
    }

    let number: Int
    let title: String
    // Snake-case decoding maps `html_url` to exactly this name.
    // swiftformat:disable:next acronyms
    let htmlUrl: String
    let head: Ref
    let base: Ref
    let state: String
    let body: String?
    let user: User?
    // swiftlint:disable:next discouraged_optional_boolean
    let draft: Bool?
    let autoMerge: AutoMerge?
    let mergedAt: Date?
    let closedAt: Date?
}
