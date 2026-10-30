import Foundation
@testable import SanductorData
import SanductorDomain
import Synchronization
import Testing

extension GitHubClientTests {
    @Test(arguments: [
        (#"{"merged":true,"autoMergeRequest":null,"mergeQueueEntry":null}"#, GitHubClient.MergeResult.merged),
        (#"{"merged":false,"autoMergeRequest":{},"mergeQueueEntry":{"id":"entry"}}"#, .enqueued),
        (#"{"merged":false,"autoMergeRequest":{},"mergeQueueEntry":null}"#, .pending),
    ])
    func `successful queue commands confirm GitHub state`(
        state: String, outcome: GitHubClient.MergeResult,
    ) async throws {
        let runner = AsyncMergeRunner(responses: [(200, ""), (200, state)])
        #expect(try await GitHubClient(runner: runner) { true }.merge(
            repositoryPath: "/repo", number: 7, usingMergeQueue: true,
        ) == outcome)
        let calls = runner.calls.withLock { $0 }
        #expect(calls.count == 2)
        #expect(calls.first == ["gh", "pr", "merge", "7"])
        #expect(calls.last?.contains("graphql") == true)
        #expect(calls.last?.contains("number=7") == true)
        let query = try #require(calls.last?.first { $0.hasPrefix("query=") })
        #expect(query.contains("mergeQueueEntry"))
        #expect(query.contains("autoMergeRequest"))
    }

    @Test(arguments: [#"{"merged":false,"autoMergeRequest":null,"mergeQueueEntry":null}"#, "", "null"])
    func `unconfirmed queue commands fall back to async`(state: String) async throws {
        let runner = AsyncMergeRunner(responses: [
            (200, ""), (200, state), (200, #"{"status":"enqueued","details":{}}"#),
        ])
        #expect(try await GitHubClient(runner: runner) { true }.merge(
            repositoryPath: "/repo", number: 7, usingMergeQueue: true,
        ) == .enqueued)
        let calls = runner.calls.withLock { $0 }
        #expect(calls.count == 3)
        #expect(calls.last?.contains("repos/{owner}/{repo}/pulls/7/merge-async") == true)
    }

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
            (200, #"{"status":"enqueued","details":{}}"#),
        ])
        #expect(try await GitHubClient(runner: runner) { true }.merge(repositoryPath: "/repo", number: 7) == .enqueued)
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
            responses: [(200, #"{"status":"enqueued","details":{}}"#)],
            firstFailure: URLError(.cannotConnectToHost),
        )
        #expect(try await GitHubClient(runner: runner) { true }.merge(repositoryPath: "/repo", number: 7) == .enqueued)
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
    func `pending queue requests are followed to admission`(status: Int) async throws {
        let runner = AsyncMergeRunner(responses: [
            (405, #"{"message":"Use the async API"}"#),
            (status, #"{"status":"pending","details":{"uuid":"630b9d5e-3f2a-4f7e-8b0c-2d5f9a8c1e42"}}"#),
            (200, #"{"status":"enqueued","details":{}}"#),
        ])
        let github = GitHubClient(runner: runner) { true }
        #expect(try await github.merge(repositoryPath: "/repo", number: 7, usingMergeQueue: true) == .enqueued)
        let calls = runner.calls.withLock { $0 }
        #expect(calls.count == 3)
        #expect(calls.first == ["gh", "pr", "merge", "7"])
        #expect(calls[1].contains("PUT"))
        #expect(calls[1].contains("repos/{owner}/{repo}/pulls/7/merge-async"))
        #expect(calls[1].contains("merge_method=rebase") == false)
        #expect(calls[1].contains("merge_action=default"))
        #expect(calls[1].contains("bypass_rules=true") == false)
        #expect(calls.last?.contains("GET") == true)
        #expect(calls.last?.contains(
            "repos/{owner}/{repo}/pulls/7/merge-async/630b9d5e-3f2a-4f7e-8b0c-2d5f9a8c1e42",
        ) == true)
    }

    @Test
    func `accepted requests report a later GitHub failure`() async {
        let runner = AsyncMergeRunner(responses: [
            (405, #"{"message":"Use the async API"}"#),
            (202, #"{"status":"pending","details":{"uuid":"630b9d5e-3f2a-4f7e-8b0c-2d5f9a8c1e42"}}"#),
            (200, #"{"status":"failed","details":{"message":"Required checks have not passed."}}"#),
        ])
        let failure = await #expect(throws: Error.self) {
            try await GitHubClient(runner: runner) { true }.merge(repositoryPath: "/repo", number: 7)
        }
        #expect(failure?.localizedDescription.contains("Required checks have not passed.") == true)
        #expect(runner.calls.withLock { $0.count } == 3)
    }

    @Test(arguments: [GitHubClient.MergeResult.merged, .enqueued])
    func `completed merge requests need no polling`(outcome: GitHubClient.MergeResult) async throws {
        let runner = AsyncMergeRunner(responses: [
            (405, #"{"message":"Use the async API"}"#),
            (200, #"{"status":"\#(outcome.rawValue)","details":{}}"#),
        ])
        #expect(try await GitHubClient(runner: runner) { true }.merge(
            repositoryPath: "/repo", number: 7, usingMergeQueue: true,
        ) == outcome)
        #expect(runner.calls.withLock { $0.count } == 2)
    }

    @Test
    func `async merge failures report GitHub's reason`() async {
        let runner = AsyncMergeRunner(responses: [
            (405, #"{"message":"Use the async API"}"#),
            (200, #"{"status":"failed","details":{"message":"Required checks have not passed."}}"#),
        ])
        let failure = await #expect(throws: Error.self) {
            try await GitHubClient(runner: runner) { true }.merge(
                repositoryPath: "/repo", number: 7, usingMergeQueue: true,
            )
        }
        #expect(failure?.localizedDescription.contains("Required checks have not passed.") == true)
    }

    @Test(arguments: [
        "{}",
        #"{"status":"unknown","details":{}}"#,
        #"{"status":"pending","details":{}}"#,
        #"{"status":"pending","details":{"uuid":"../other"}}"#,
        "not JSON",
    ])
    func `invalid merge responses never count as success`(body: String) async {
        let runner = AsyncMergeRunner(responses: [
            (405, #"{"message":"Use the async API"}"#), (200, body),
        ])
        await #expect(throws: Error.self) {
            try await GitHubClient(runner: runner) { true }.merge(
                repositoryPath: "/repo", number: 7, usingMergeQueue: true,
            )
        }
        #expect(runner.calls.withLock { $0.count } == 2)
    }

    @Test
    func `requests that remain pending report an unconfirmed result`() async {
        let runner = AsyncMergeRunner(responses: [(405, #"{"message":"Use the async API"}"#)] + Array(
            repeating: (200, #"{"status":"pending","details":{"uuid":"630b9d5e-3f2a-4f7e-8b0c-2d5f9a8c1e42"}}"#),
            count: RefreshCadence.mergeResultTimeout / RefreshCadence.mergeResultSeconds + 2,
        ))
        let failure = await #expect(throws: Error.self) {
            try await mergeClient(runner).merge(repositoryPath: "/repo", number: 7)
        }
        #expect(failure?.localizedDescription.contains("GitHub has not confirmed") == true)
        #expect(runner.calls.withLock { $0 }.count { $0.contains("PUT") } == 2)
    }

    @Test(arguments: [(false, false), (true, true), (false, true)])
    func `slow polling checks once more at the deadline`(visible: Bool, onBattery: Bool) async throws {
        let runner = AsyncMergeRunner(responses: [
            (405, #"{"message":"Use the async API"}"#),
            (202, #"{"status":"pending","details":{"uuid":"630b9d5e-3f2a-4f7e-8b0c-2d5f9a8c1e42"}}"#),
            (200, #"{"status":"pending","details":{"uuid":"630b9d5e-3f2a-4f7e-8b0c-2d5f9a8c1e42"}}"#),
            (200, #"{"status":"enqueued","details":{}}"#),
        ])
        let github = mergeClient(runner, interval: .seconds(RefreshCadence.pollSeconds(
            setting: RefreshCadence.mergeResultSeconds, visible: visible, onBattery: onBattery,
        )))
        #expect(try await github.merge(repositoryPath: "/repo", number: 7) == .enqueued)
        #expect(runner.calls.withLock { $0 }.count { $0.contains("GET") } == 2)
    }

    @Test
    func `a failed result read retries without resubmitting the merge`() async throws {
        let runner = AsyncMergeRunner(responses: [
            (405, #"{"message":"Use the async API"}"#),
            (202, #"{"status":"pending","details":{"uuid":"630b9d5e-3f2a-4f7e-8b0c-2d5f9a8c1e42"}}"#),
            (502, #"{"message":"Bad gateway"}"#),
            (200, #"{"status":"enqueued","details":{}}"#),
        ])
        #expect(try await mergeClient(runner).merge(repositoryPath: "/repo", number: 7) == .enqueued)
        #expect(runner.calls.withLock { $0 }.count { $0.contains("PUT") } == 2)
        #expect(runner.calls.withLock { $0 }.count { $0.contains("GET") } == 2)
    }

    @Test
    func `a result transport failure retries without resubmitting the merge`() async throws {
        let runner = AsyncMergeRunner(responses: [
            (405, #"{"message":"Use the async API"}"#),
            (202, #"{"status":"pending","details":{"uuid":"630b9d5e-3f2a-4f7e-8b0c-2d5f9a8c1e42"}}"#),
            (200, #"{"status":"enqueued","details":{}}"#),
        ], pollFailure: URLError(.networkConnectionLost))
        #expect(try await mergeClient(runner).merge(repositoryPath: "/repo", number: 7) == .enqueued)
        #expect(runner.calls.withLock { $0 }.count { $0.contains("PUT") } == 2)
        #expect(runner.calls.withLock { $0 }.count { $0.contains("GET") } == 2)
    }

    @Test
    func `repeated failed result reads end as unconfirmed`() async {
        let runner = AsyncMergeRunner(responses: [
            (405, #"{"message":"Use the async API"}"#),
            (202, #"{"status":"pending","details":{"uuid":"630b9d5e-3f2a-4f7e-8b0c-2d5f9a8c1e42"}}"#),
        ] + Array(repeating: (502, #"{"message":"Bad gateway"}"#), count: 2))
        let failure = await #expect(throws: Error.self) {
            try await mergeClient(runner, interval: .seconds(60)).merge(repositoryPath: "/repo", number: 7)
        }
        #expect(failure?.localizedDescription.contains("GitHub has not confirmed") == true)
        #expect(runner.calls.withLock { $0 }.count { $0.contains("PUT") } == 2)
        #expect(runner.calls.withLock { $0 }.count { $0.contains("GET") } == 2)
    }

    @Test
    func `cancelling a result read stops polling`() async {
        let runner = AsyncMergeRunner(responses: [
            (405, #"{"message":"Use the async API"}"#),
            (202, #"{"status":"pending","details":{"uuid":"630b9d5e-3f2a-4f7e-8b0c-2d5f9a8c1e42"}}"#),
        ], pollFailure: CancellationError())
        await #expect(throws: CancellationError.self) {
            try await mergeClient(runner).merge(repositoryPath: "/repo", number: 7)
        }
        #expect(runner.calls.withLock { $0.count } == 3)
    }

    @Test(arguments: [400, 403, 404, 409, 422])
    func `rejected fallbacks are not retried`(status: Int) async {
        let runner = AsyncMergeRunner(responses: [
            (405, #"{"message":"Use the async API"}"#), (status, #"{"message":"Rejected"}"#),
        ])
        await #expect(throws: Error.self) {
            try await GitHubClient(runner: runner) { true }.merge(
                repositoryPath: "/repo", number: 7, usingMergeQueue: true,
            )
        }
        #expect(runner.calls.withLock { $0.count } == 2)
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

    private func mergeClient(
        _ runner: AsyncMergeRunner, interval: Duration = .seconds(RefreshCadence.mergeResultSeconds),
    ) -> GitHubClient {
        let instant = Mutex(ContinuousClock.now)
        var github = GitHubClient(runner: runner) { true }
        github.mergePolling.now = { instant.withLock { $0 } }
        github.mergePolling.interval = { interval }
        github.mergePolling.sleep = { duration in
            try Task.checkCancellation()
            instant.withLock { $0 += duration }
        }
        return github
    }
}

// MARK: - AsyncMergeRunner

private final class AsyncMergeRunner: ProcessRunner, Sendable {
    // MARK: Lifecycle

    init(responses: [(Int, String)], firstFailure: any Error? = nil, pollFailure: any Error? = nil) {
        self.responses = Mutex(responses)
        self.firstFailure = Mutex(firstFailure)
        self.pollFailure = Mutex(pollFailure)
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
        if arguments.contains("GET"), let failure = pollFailure.withLock({ failure in
            defer { failure = nil }
            return failure
        }) {
            throw failure
        }
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
            standardOutput: (arguments.contains("--include") ? "HTTP/2.0 \(status) Response\r\n\r\n" : "") + body,
            standardError: status < failureStatus ? "" : "gh: Rejected (HTTP \(status))",
        )
    }

    // MARK: Private

    private let responses: Mutex<[(Int, String)]>
    private let firstFailure: Mutex<any Error?>
    private let pollFailure: Mutex<any Error?>
}
