@testable import AgentIDEData
import Foundation
import Synchronization
import Testing

extension GitHubClientTests {
    @Test
    func `plain pull requests merge synchronously`() async throws {
        let runner = AsyncMergeRunner(responses: [(200, #"{"merged":true}"#)])
        #expect(try await GitHubClient(runner: runner) { true }.merge(repositoryPath: "/repo", number: 7) == .merged)
        let calls = runner.calls.withLock { $0 }
        #expect(calls.count == 1)
        #expect(calls[0].contains("repos/{owner}/{repo}/pulls/7/merge"))
        #expect(calls[0].contains("merge_method=rebase"))
        #expect(calls[0].contains("merge_action=default") == false)
    }

    @Test(arguments: [403, 404, 405, 409, 422, 500])
    func `synchronous merge failures fall back to async`(status: Int) async throws {
        let runner = AsyncMergeRunner(responses: [
            (status, #"{"message":"Use the async API"}"#),
            (202, #"{"status":"pending","details":{}}"#),
        ])
        #expect(try await GitHubClient(runner: runner) { true }.merge(repositoryPath: "/repo", number: 7) == .pending)
        let calls = runner.calls.withLock { $0 }
        #expect(calls.count == 2)
        #expect(calls[0].contains("repos/{owner}/{repo}/pulls/7/merge"))
        #expect(calls[1].contains("repos/{owner}/{repo}/pulls/7/merge-async"))
        #expect(calls[1].contains("merge_method=rebase"))
        #expect(calls[1].contains("merge_action=default"))
    }

    @Test(arguments: [#"{"merged":false,"message":"Not merged"}"#, "{}", "not JSON"])
    func `unconfirmed synchronous merges fall back to async`(body: String) async throws {
        let runner = AsyncMergeRunner(responses: [(200, body), (200, #"{"status":"enqueued","details":{}}"#)])
        #expect(try await GitHubClient(runner: runner) { true }.merge(repositoryPath: "/repo", number: 7) == .enqueued)
        #expect(runner.calls.withLock { $0.count } == 2)
    }

    @Test
    func `a synchronous transport failure falls back to async`() async throws {
        let runner = AsyncMergeRunner(
            responses: [(202, #"{"status":"pending","details":{}}"#)],
            firstFailure: URLError(.cannotConnectToHost),
        )
        #expect(try await GitHubClient(runner: runner) { true }.merge(repositoryPath: "/repo", number: 7) == .pending)
        #expect(runner.calls.withLock { $0.count } == 2)
    }

    @Test
    func `cancelling a synchronous merge does not submit an async request`() async {
        let runner = AsyncMergeRunner(responses: [], firstFailure: CancellationError())
        await #expect(throws: CancellationError.self) {
            try await GitHubClient(runner: runner) { true }.merge(repositoryPath: "/repo", number: 7)
        }
        #expect(runner.calls.withLock { $0.count } == 1)
    }

    @Test
    func `failed sync and async merges report both attempts`() async {
        let runner = AsyncMergeRunner(responses: [
            (405, #"{"message":"Sync refused"}"#),
            (403, #"{"message":"Async refused"}"#),
        ])
        let failure = await #expect(throws: Error.self) {
            try await GitHubClient(runner: runner) { true }.merge(repositoryPath: "/repo", number: 7)
        }
        #expect(failure?.localizedDescription.contains("Synchronous merge failed:") == true)
        #expect(failure?.localizedDescription.contains("HTTP 405") == true)
        #expect(failure?.localizedDescription.contains("Asynchronous merge failed:") == true)
        #expect(failure?.localizedDescription.contains("HTTP 403") == true)
        #expect(runner.calls.withLock { $0.count } == 2)
    }

    @Test(arguments: [202, 409])
    func `pending merges return without polling`(status: Int) async throws {
        let runner = AsyncMergeRunner(responses: [
            (status, #"{"status":"pending","details":{"uuid":"630b9d5e-3f2a-4f7e-8b0c-2d5f9a8c1e42"}}"#),
        ])
        let github = GitHubClient(runner: runner) { true }
        #expect(try await github.merge(repositoryPath: "/repo", number: 7, asynchronously: true) == .pending)
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
        #expect(try await GitHubClient(runner: runner) { true }.merge(
            repositoryPath: "/repo", number: 7, asynchronously: true,
        ) == outcome)
        #expect(runner.calls.withLock { $0.count } == 1)
    }

    @Test
    func `async merge failures report GitHub's reason`() async {
        let runner = AsyncMergeRunner(responses: [
            (200, #"{"status":"failed","details":{"message":"Required checks have not passed."}}"#),
        ])
        let failure = await #expect(throws: Error.self) {
            try await GitHubClient(runner: runner) { true }.merge(
                repositoryPath: "/repo", number: 7, asynchronously: true,
            )
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
            try await GitHubClient(runner: runner) { true }.merge(
                repositoryPath: "/repo", number: 7, asynchronously: true,
            )
        }
        #expect(runner.calls.withLock { $0.count } == 1)
    }

    @Test(arguments: [400, 403, 404, 409, 422])
    func `rejected merge requests are not retried`(status: Int) async {
        let runner = AsyncMergeRunner(responses: [(status, #"{"message":"Rejected"}"#)])
        await #expect(throws: Error.self) {
            try await GitHubClient(runner: runner) { true }.merge(
                repositoryPath: "/repo", number: 7, asynchronously: true,
            )
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

    init(responses: [(Int, String)], firstFailure: (any Error)? = nil) {
        self.responses = Mutex(responses)
        self.firstFailure = Mutex(firstFailure)
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
        if let failure = firstFailure.withLock({ failure in
            defer { failure = nil }
            return failure
        }) {
            throw failure
        }
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
    private let firstFailure: Mutex<(any Error)?>
}
