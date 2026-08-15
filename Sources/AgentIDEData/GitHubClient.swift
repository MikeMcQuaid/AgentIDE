import AgentIDEDomain
import Foundation

/// Talks to GitHub through the host user's authenticated `gh` CLI;
/// the sandbox never sees these credentials.
public struct GitHubClient: Sendable {
    // MARK: Lifecycle

    /// Creates a client.
    public init(runner: any ProcessRunner) {
        self.runner = runner
    }

    // MARK: Public

    /// Which pull requests a listing covers.
    public enum ListScope: Hashable, Sendable {
        /// Open and closed pull requests from one branch.
        case branch(String)
        /// Open pull requests the authenticated user created.
        case mine
        /// Every open pull request.
        case open
    }

    /// The `gh pr list` page size, public so it can default the
    /// public listing's limit. The branch scope filters server-side
    /// so one page is plenty, and the pull request tab raises the
    /// limit as later pages are visited.
    public static let listLimit = 25

    /// The repository's pull request template file content, nil
    /// without one.
    public static func pullRequestTemplate(in worktreePath: String) -> String? {
        [
            ".github/PULL_REQUEST_TEMPLATE.md",
            ".github/pull_request_template.md",
            "PULL_REQUEST_TEMPLATE.md",
            "docs/PULL_REQUEST_TEMPLATE.md",
        ]
        .map { worktreePath + "/" + $0 }
        .first { FileManager.default.fileExists(atPath: $0) }
        .flatMap { try? String(contentsOfFile: $0, encoding: .utf8) }
    }

    /// The repository's pull requests for a scope, with dashboard
    /// state.
    public func pullRequests(
        repositoryPath: String,
        scope: ListScope = .open,
        limit: Int = Self.listLimit,
    ) async throws -> [PullRequestSummary] {
        let result = try await gh(Self.listArguments(scope: scope, limit: limit), in: repositoryPath)
        return Self.summaries(fromJSON: result.standardOutput)
    }

    /// One pull request's full summary, fetched when a light list
    /// row clicks through so its header gains the status icons.
    public func pullRequestSummary(
        repositoryPath: String,
        number: Int,
    ) async throws -> PullRequestSummary? {
        let fields = Self.coreFields + "," + Self.statusFields
        let result = try await gh(["pr", "view", String(number), "--json", fields], in: repositoryPath)
        return Self.summaries(fromJSON: "[" + result.standardOutput + "]").first
    }

    /// The authenticated user's login followed by their
    /// organisations, for the repository finder's owner step.
    public func organisations(directory: String) async throws -> [String] {
        // gh's HTTP cache answers repeats for an hour; memberships
        // change rarely.
        let user = try await gh(["api", "user", "--cache", "1h", "--jq", ".login"], in: directory)
        let organisations = try await gh(
            ["api", "user/orgs?per_page=100", "--cache", "1h", "--paginate", "--jq", ".[].login"],
            in: directory,
        )
        let login = user.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return ([login] + organisations.standardOutput.split(separator: "\n").map(String.init))
            .filter { $0.isEmpty == false }
    }

    /// Every repository under one owner, as `owner/name`, most
    /// recently pushed first.
    public func repositories(owner: String, directory: String) async throws -> [String] {
        let result = try await gh(
            ["repo", "list", owner, "--limit", "1000", "--json", "nameWithOwner", "--jq", ".[].nameWithOwner"],
            in: directory,
        )
        return result.standardOutput.split(separator: "\n").map(String.init)
    }

    /// Clones a repository into a directory, named after the
    /// repository, using the host's credentials.
    public func clone(fullName: String, into directory: String) async throws {
        let name = fullName.split(separator: "/").last.map(String.init) ?? fullName
        try await gh(["repo", "clone", fullName, name], in: directory)
    }

    /// Whether the repository merges through a merge queue, so merge
    /// controls can say queue rather than merge.
    public func hasMergeQueue(repositoryPath: String) async -> Bool {
        let nameWithOwner = try? await gh(
            ["repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner"],
            in: repositoryPath,
        )
        .standardOutput
        .trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = (nameWithOwner ?? "").split(separator: "/", maxSplits: 1)
        guard let owner = parts.first, let name = parts.dropFirst().first else {
            return false
        }

        let query = "query($owner: String!, $name: String!) "
            + "{ repository(owner: $owner, name: $name) { mergeQueue { id } } }"
        // A repository setting that rarely changes; gh's HTTP cache
        // answers repeats for a day.
        let result = try? await gh(
            [
                "api", "graphql", "--cache", "24h",
                "-f", "query=" + query,
                "-f", "owner=" + String(owner),
                "-f", "name=" + String(name),
            ],
            in: repositoryPath,
        )
        return result?.standardOutput.contains("\"mergeQueue\":{") ?? false
    }

    /// The repository's `owner/name`, nil when unknown; a setting
    /// that rarely changes, so gh's HTTP cache answers repeats.
    public func fullName(repositoryPath: String) async -> String? {
        let result = try? await gh(
            ["repo", "view", "--json", "nameWithOwner", "--cache", "1h", "--jq", ".nameWithOwner"],
            in: repositoryPath,
        )
        let name = result?.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? nil : name
    }

    /// Opens a pull request from the worktree's branch; returns its
    /// URL. The body travels by file: it can hold anything.
    public func createPullRequest(worktreePath: String, title: String, body: String) async throws -> String {
        let bodyFile = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("agentide-pr-body-" + UUID().uuidString + ".md")
            .path
        try body.write(toFile: bodyFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: bodyFile) }
        return try await gh(["pr", "create", "--title", title, "--body-file", bodyFile], in: worktreePath)
            .standardOutput
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Enables automerge for a pull request.
    public func enableAutomerge(repositoryPath: String, number: Int) async throws {
        try await gh(["pr", "merge", String(number), "--auto", "--squash"], in: repositoryPath)
    }

    /// Merges a pull request immediately.
    public func merge(repositoryPath: String, number: Int) async throws {
        try await gh(["pr", "merge", String(number), "--squash"], in: repositoryPath)
    }

    // MARK: Internal

    /// Cheap fields, including the body so a click-through shows the
    /// conversation immediately.
    static let coreFields = "number,title,url,headRefName,baseRefName,state,isDraft,author,body"

    /// The expensive dashboard fields; computing these across every
    /// open pull request timed out (HTTP 504) on busy repositories,
    /// so the open scope skips them and rows enrich on selection.
    static let statusFields = "mergeable,reviewDecision,statusCheckRollup,autoMergeRequest,headRefOid"

    static func listArguments(scope: ListScope, limit: Int = Self.listLimit) -> [String] {
        let fields = scope == .open ? Self.coreFields : Self.coreFields + "," + Self.statusFields
        var arguments = ["pr", "list", "--json", fields, "--limit", String(limit)]
        switch scope {
        case let .branch(branch):
            arguments += ["--head", branch, "--state", "all"]

        case .mine:
            arguments += ["--author", "@me"]

        case .open:
            break
        }
        return arguments
    }

    /// Parses `gh pr list` JSON into summaries; separated for tests.
    static func summaries(fromJSON json: String) -> [PullRequestSummary] {
        guard let data = json.data(using: .utf8) else {
            return []
        }

        let rows = (try? JSONDecoder().decode([PullRequestRow].self, from: data)) ?? []
        return rows.map { row in
            let rollup = row.statusCheckRollup ?? []
            return PullRequestSummary(
                number: row.number,
                title: row.title,
                url: row.url,
                headBranch: row.headRefName,
                mergeable: row.mergeable ?? "",
                reviewDecision: row.reviewDecision ?? "",
                checks: Self.aggregateChecks(rollup),
                failingCheckLinks: rollup
                    .filter { ($0.conclusion ?? $0.state ?? "").uppercased() == "FAILURE" }
                    .compactMap(\.detailsUrl), // swiftformat:disable:this acronyms
                baseBranch: row.baseRefName ?? "",
                state: row.state ?? "OPEN",
                isDraft: row.isDraft ?? false,
                hasAutomerge: row.autoMergeRequest != nil,
                headOID: row.headRefOid ?? "",
                author: row.author?.login,
                body: row.body,
            )
        }
    }

    @discardableResult
    func gh(
        _ arguments: [String],
        in directory: String?,
        allowFailure: Bool = false,
    ) async throws -> ProcessResult {
        let result = try await runner.run(["gh"] + arguments, workingDirectory: directory, environment: [:])
        guard result.succeeded || allowFailure else {
            throw CommandError(command: "gh " + arguments.joined(separator: " "), result: result)
        }

        return result
    }

    // MARK: Private

    /// Present when automerge is enabled; the contents are unused.
    private struct AutoMergeRow: Decodable {
        // Presence is the signal.
    }

    private struct RowAuthor: Decodable {
        let login: String?
    }

    private struct PullRequestRow: Decodable {
        let number: Int
        let title: String
        let url: String
        let headRefName: String
        let baseRefName: String?
        let state: String?
        let mergeable: String?
        let reviewDecision: String?
        let author: RowAuthor?
        let body: String?
        // Optional because older gh versions omit the field.
        // swiftlint:disable:next discouraged_optional_boolean
        let isDraft: Bool?
        let autoMergeRequest: AutoMergeRow?
        let headRefOid: String?
        // Absent from the JSON when a pull request has no checks.
        // swiftlint:disable:next discouraged_optional_collection
        let statusCheckRollup: [CheckRow]?
    }

    private struct CheckRow: Decodable {
        let state: String?
        let conclusion: String?
        // The property must match gh's JSON key exactly.
        // swiftformat:disable:next acronyms
        let detailsUrl: String?
    }

    private let runner: any ProcessRunner

    private static func aggregateChecks(_ rows: [CheckRow]) -> String {
        let states = rows.map { ($0.conclusion ?? $0.state ?? "").uppercased() }
        guard states.isEmpty == false else {
            return ""
        }

        if states.contains(where: { $0 == "FAILURE" || $0 == "ERROR" }) {
            return "FAILURE"
        }
        if states.allSatisfy({ $0 == "SUCCESS" || $0 == "NEUTRAL" || $0 == "SKIPPED" }) {
            return "SUCCESS"
        }
        return "PENDING"
    }
}
