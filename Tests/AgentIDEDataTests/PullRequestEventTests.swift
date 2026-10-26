@testable import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

// MARK: - PullRequestEventTests

struct PullRequestEventTests {
    // MARK: Internal

    @Test
    func `comments keep the state clock and unchanged reads reuse it`() async throws {
        let runner = StateEventRunner()
        let metadata = try MetadataStore(file: TestSupport.temporaryDirectory("state-events") + "/state.json")
        let store = PullRequestStore(github: GitHubClient(runner: runner) { true }, store: metadata) { false }
        let original = Self.summary(updatedAt: 200)
        let first = await store.withStateChange(original, previous: nil, repositoryPath: "/repo")
        #expect(first.stateChangedAt == Date(timeIntervalSince1970: 100))
        let repeated = await store.withStateChange(original, previous: first, repositoryPath: "/repo")
        #expect(repeated.stateChangedAt == first.stateChangedAt)
        #expect(await runner.calls == 1)

        let comment = Self.summary(updatedAt: 300)
        let commented = await store.withStateChange(comment, previous: repeated, repositoryPath: "/repo")
        #expect(commented.stateChangedAt == first.stateChangedAt)
        #expect(await runner.calls == 2)

        metadata.update { $0.queuedCache["/repo"] = [7] }
        await runner.setEvent("1970-01-01T00:06:40Z")
        let queued = await store.withStateChange(comment, previous: commented, repositoryPath: "/repo")
        #expect(queued.isQueued)
        #expect(queued.stateChangedAt == Date(timeIntervalSince1970: 400))
        #expect(await runner.calls == 3)
    }

    @Test
    func `opening time is used when there are no later state changes`() async throws {
        let runner = StateEventRunner()
        await runner.setEvent(nil)
        let client = GitHubClient(runner: runner) { true }
        #expect(try await client.stateChangedAt(repositoryPath: "/repo", number: 7) == Date(timeIntervalSince1970: 0))
        let arguments = await runner.arguments
        let query = try #require(arguments.first { $0.hasPrefix("query=") })
        #expect(query.contains("last: 1"))
        #expect(query.contains("ADDED_TO_MERGE_QUEUE_EVENT"))
        #expect(query.contains("REMOVED_FROM_MERGE_QUEUE_EVENT"))
        #expect(query.contains("ISSUE_COMMENT") == false)
        #expect(query.contains("PULL_REQUEST_REVIEW") == false)
    }

    // MARK: Private

    private static func summary(updatedAt: TimeInterval) -> PullRequestSummary {
        PullRequestSummary(
            number: 7,
            title: "Work",
            url: "",
            headBranch: "work",
            mergeable: "",
            reviewDecision: "",
            checks: "",
            updatedAt: Date(timeIntervalSince1970: updatedAt),
        )
    }
}

// MARK: - StateEventRunner

private actor StateEventRunner: ProcessRunner {
    // MARK: Internal

    private(set) var calls = 0
    private(set) var arguments: [String] = []

    func setEvent(_ event: String?) {
        self.event = event
    }

    func run(
        _ arguments: [String], workingDirectory _: String?, environment _: [String: String], outputLimit _: Int?,
    ) -> ProcessResult {
        calls += 1
        self.arguments = arguments
        let nodes = event.map { "{\"createdAt\":\"" + $0 + "\"}" } ?? ""
        return ProcessResult(
            status: 0,
            standardOutput: "{\"createdAt\":\"1970-01-01T00:00:00Z\",\"timelineItems\":{\"nodes\":[" + nodes + "]}}",
            standardError: "",
        )
    }

    // MARK: Private

    private var event: String? = "1970-01-01T00:01:40Z"
}
