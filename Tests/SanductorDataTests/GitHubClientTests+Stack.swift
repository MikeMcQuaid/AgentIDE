import Foundation
@testable import SanductorData
import SanductorDomain
import Synchronization
import Testing

extension GitHubClientTests {
    @Test
    func `REST stack positions survive missing neighbouring pull requests`() throws {
        let json = """
        [{"number":7,"title":"Work","html_url":"https://github.com/o/r/pull/7",
          "head":{"ref":"top"},"base":{"ref":"middle"},"state":"open",
          "stack":{"number":42,"size":3,"position":3,"base":{"ref":"main","sha":"base"}}}]
        """
        let summary = try #require(GitHubClient.summaries(fromRESTJSON: json).first)
        let standing = StackStanding(position: 3, height: 3, base: "middle")
        #expect(summary.stackStanding == standing)
        #expect(summary.retitled("Updated", body: "Body").stackStanding == standing)
        #expect(summary.awaitingChecks().stackStanding == standing)
        let saved = try JSONEncoder().encode(summary)
        #expect(try JSONDecoder().decode(PullRequestSummary.self, from: saved).stackStanding == standing)
    }

    @Test(arguments: [
        "null", #"{"base":{"ref":"main","sha":"base"}}"#,
        #"{"size":2,"position":0}"#, #"{"size":2,"position":3}"#,
    ])
    func `missing or invalid stack positions keep the pull request readable`(stack: String) throws {
        let json = """
        [{"number":7,"title":"Work","html_url":"https://github.com/o/r/pull/7",
          "head":{"ref":"top"},"base":{"ref":"middle"},"state":"open","stack":\(stack)}]
        """
        let summary = try #require(GitHubClient.summaries(fromRESTJSON: json).first)
        #expect(summary.stackStanding == nil)
    }

    @Test
    func `linking creates a stack through the REST API`() async throws {
        let runner = StackAPIRunner()
        try await GitHubClient(runner: runner) { true }.linkStack(worktreePath: "/repo", numbers: [12, 7])
        let calls = runner.calls.withLock { $0 }
        #expect(calls.count == 3)
        #expect(calls.last == [
            "gh", "api", "--method", "POST", "--header", "Accept: application/vnd.github+json",
            "--header", "X-GitHub-Api-Version: 2026-03-10", "repos/{owner}/{repo}/stacks",
            "--field", "pull_requests[]=12", "--field", "pull_requests[]=7",
        ])
    }

    @Test
    func `linking an existing stack appends only new members`() async throws {
        let runner = StackAPIRunner(stacks: [12: Self.stackJSON])
        try await GitHubClient(runner: runner) { true }.linkStack(worktreePath: "/repo", numbers: [12, 7, 9])
        let calls = runner.calls.withLock { $0 }
        #expect(calls.count == 3)
        #expect(calls.last?.contains("repos/{owner}/{repo}/stacks/42/add") == true)
        #expect(calls.last?.suffix(2) == ["--field", "pull_requests[]=9"])
        #expect(calls.last?.contains("pull_requests[]=12") == false)
    }

    @Test(arguments: [[12, 7], [12], [7]])
    func `linking existing members leaves the stack untouched`(numbers: [Int]) async throws {
        let runner = StackAPIRunner(stacks: [12: Self.stackJSON, 7: Self.stackJSON])
        try await GitHubClient(runner: runner) { true }.linkStack(worktreePath: "/repo", numbers: numbers)
        #expect(runner.calls.withLock { $0 }.allSatisfy { $0.contains("POST") == false })
    }

    @Test(arguments: [[7, 12], [12, 9, 7], [12, 9], [12, 12]])
    func `linking refuses incompatible membership without writing`(numbers: [Int]) async {
        let runner = StackAPIRunner(stacks: [12: Self.stackJSON, 7: Self.stackJSON])
        await #expect(throws: (any Error).self) {
            try await GitHubClient(runner: runner) { true }.linkStack(worktreePath: "/repo", numbers: numbers)
        }
        #expect(runner.calls.withLock { $0 }.allSatisfy { $0.contains("POST") == false })
    }

    @Test
    func `linking refuses members of different stacks`() async {
        let runner = StackAPIRunner(stacks: [
            12: Self.stackJSON,
            9: #"[{"number":43,"open":true,"pull_requests":[{"number":9},{"number":10}]}]"#,
        ])
        await #expect(throws: (any Error).self) {
            try await GitHubClient(runner: runner) { true }.linkStack(worktreePath: "/repo", numbers: [12, 7, 9])
        }
        #expect(runner.calls.withLock { $0 }.allSatisfy { $0.contains("POST") == false })
    }

    @Test(arguments: ["not JSON", "{}"])
    func `unreadable stack membership never creates a stack`(response: String) async {
        let runner = StackAPIRunner(stacks: [12: response])
        await #expect(throws: (any Error).self) {
            try await GitHubClient(runner: runner) { true }.linkStack(worktreePath: "/repo", numbers: [12, 7])
        }
        #expect(runner.calls.withLock { $0 }.allSatisfy { $0.contains("POST") == false })
    }

    private static let stackJSON = #"[{"number":42,"open":true,"pull_requests":[{"number":12},{"number":7}]}]"#
}

// MARK: - StackAPIRunner

private final class StackAPIRunner: ProcessRunner, Sendable {
    // MARK: Lifecycle

    init(stacks: [Int: String] = [:]) {
        self.stacks = stacks
    }

    deinit {
        // Nothing to clean up.
    }

    // MARK: Internal

    let calls: Mutex = .init([[String]]())

    func run(
        _ arguments: [String],
        workingDirectory: String?,
        environment _: [String: String],
        outputLimit _: Int?,
    ) -> ProcessResult {
        #expect(workingDirectory == "/repo")
        calls.withLock { $0.append(arguments) }
        let number = arguments.first { $0.hasPrefix("repos/{owner}/{repo}/stacks?pull_request=") }
            .flatMap { $0.split(separator: "=").last }
            .flatMap { Int($0) }
        return ProcessResult(status: 0, standardOutput: number.flatMap { stacks[$0] } ?? "[]", standardError: "")
    }

    // MARK: Private

    private let stacks: [Int: String]
}
