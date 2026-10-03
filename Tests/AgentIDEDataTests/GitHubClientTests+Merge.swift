@testable import AgentIDEData
import Foundation
import Synchronization
import Testing

extension GitHubClientTests {
    @Test(arguments: [202, 409])
    func `pending merges return without polling`(status: Int) async throws {
        let runner = AsyncMergeRunner(responses: [
            (status, #"{"status":"pending","details":{"uuid":"630b9d5e-3f2a-4f7e-8b0c-2d5f9a8c1e42"}}"#),
        ])
        let github = GitHubClient(runner: runner) { true }
        #expect(try await github.merge(repositoryPath: "/repo", number: 7) == .pending)
        let calls = runner.calls.withLock { $0 }
        #expect(calls.count == 1)
        #expect(calls.first?.contains("PUT") == true)
        #expect(calls.first?.contains("repos/{owner}/{repo}/pulls/7/merge-async") == true)
        #expect(calls.first?.contains("merge_method=rebase") == true)
        #expect(calls.first?.contains("merge_action=default") == true)
        #expect(calls.first?.contains("bypass_rules=true") == false)
    }

    @Test(arguments: [GitHubClient.MergeResult.merged, .enqueued])
    func `completed merge requests need no polling`(outcome: GitHubClient.MergeResult) async throws {
        let runner = AsyncMergeRunner(responses: [(200, #"{"status":"\#(outcome.rawValue)","details":{}}"#)])
        #expect(try await GitHubClient(runner: runner) { true }.merge(repositoryPath: "/repo", number: 7) == outcome)
        #expect(runner.calls.withLock { $0.count } == 1)
    }

    @Test
    func `async merge failures report GitHub's reason`() async {
        let runner = AsyncMergeRunner(responses: [
            (200, #"{"status":"failed","details":{"message":"Required checks have not passed."}}"#),
        ])
        let failure = await #expect(throws: Error.self) {
            try await GitHubClient(runner: runner) { true }.merge(repositoryPath: "/repo", number: 7)
        }
        #expect(failure?.localizedDescription.contains("Required checks have not passed.") == true)
    }

    @Test(arguments: [
        "{}",
        #"{"status":"unknown","details":{}}"#,
        "not JSON",
    ])
    func `invalid merge responses never count as success`(body: String) async {
        let runner = AsyncMergeRunner(responses: [(200, body)])
        await #expect(throws: Error.self) {
            try await GitHubClient(runner: runner) { true }.merge(repositoryPath: "/repo", number: 7)
        }
        #expect(runner.calls.withLock { $0.count } == 1)
    }

    @Test(arguments: [400, 403, 404, 409, 422])
    func `rejected merge requests are not retried`(status: Int) async {
        let runner = AsyncMergeRunner(responses: [(status, #"{"message":"Rejected"}"#)])
        await #expect(throws: Error.self) {
            try await GitHubClient(runner: runner) { true }.merge(repositoryPath: "/repo", number: 7)
        }
        #expect(runner.calls.withLock { $0.count } == 1)
    }

    @Test
    func `automerge controls keep their existing commands`() async throws {
        let runner = RecordingRunner()
        let github = GitHubClient(runner: runner) { true }
        try await github.enableAutomerge(repositoryPath: "/repo", number: 7)
        try await github.disableAutomerge(repositoryPath: "/repo", number: 7)
        #expect(runner.commands.suffix(2) == [
            ["gh", "pr", "merge", "7", "--auto", "--merge"],
            ["gh", "pr", "merge", "7", "--disable-auto"],
        ])
    }
}

// MARK: - AsyncMergeRunner

private final class AsyncMergeRunner: ProcessRunner, Sendable {
    // MARK: Lifecycle

    init(responses: [(Int, String)]) {
        self.responses = Mutex(responses)
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
    ) throws -> ProcessResult {
        #expect(workingDirectory == "/repo")
        if arguments.starts(with: ["gh", "repo", "view"]) {
            return ProcessResult(
                status: 0,
                standardOutput: #"{"mergeCommitAllowed":false,"rebaseMergeAllowed":true}"#,
                standardError: "",
            )
        }
        calls.withLock { $0.append(arguments) }
        let (status, body) = try responses.withLock { try #require($0.isEmpty ? nil : $0.removeFirst()) }
        let failureStatus = 400
        return ProcessResult(
            status: status < failureStatus ? 0 : 1,
            standardOutput: "HTTP/2.0 \(status) Response\r\n\r\n" + body,
            standardError: status < failureStatus ? "" : "gh: Rejected (HTTP \(status))",
        )
    }

    // MARK: Private

    private let responses: Mutex<[(Int, String)]>
}
