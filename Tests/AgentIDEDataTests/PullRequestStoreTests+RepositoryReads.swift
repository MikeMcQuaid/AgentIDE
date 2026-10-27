@testable import AgentIDEData
import Foundation
import Testing

extension PullRequestStoreTests {
    @Test(arguments: ["checks", "push", "labels", "queue"])
    func `worktrees share repository settings already being read`(_ setting: String) async throws {
        let root = try TestSupport.temporaryDirectory("shared-settings")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let runner = PausedRepositoryRunner()
        let first = PullRequestStore(
            github: GitHubClient(runner: runner), store: MetadataStore(file: root + "/state.json"),
        ) { false }
        let second = PullRequestStore(
            github: GitHubClient(runner: runner), store: MetadataStore(file: root + "/state.json"),
        ) { false }
        let read: @Sendable (PullRequestStore) async -> String = { store in
            switch setting {
            case "checks":
                await store.requiredChecks(repositoryPath: "/repo", branch: "main")?.sorted().joined() ?? "unknown"

            case "push":
                await String(store.acceptsDefaultPushes(repositoryPath: "/repo", branch: "main"))

            case "labels":
                await store.labels(repositoryPath: "/repo").joined()

            default:
                await String(store.hasMergeQueue(repositoryPath: "/repo"))
            }
        }
        async let one = read(first)
        var started = runner.started.stream.makeAsyncIterator()
        _ = await started.next()
        async let two = read(second)
        try await Task.sleep(for: .milliseconds(50))
        await runner.resume()

        let expected = ["checks": "test", "push": "false", "labels": "bug", "queue": "true"][setting]
        #expect(await one == expected)
        #expect(await two == expected)
        #expect(await read(second) == expected)
        #expect(await runner.calls.count == (["checks", "push"].contains(setting) ? 2 : 1))
    }

    @Test(arguments: [false, true])
    func `sidebar and pane share overlapping merge queue reads`(sidebarFirst: Bool) async throws {
        let root = try TestSupport.temporaryDirectory("shared-queues")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let runner = PausedRepositoryRunner()
        let first = PullRequestStore(
            github: GitHubClient(runner: runner), store: MetadataStore(file: root + "/state.json"),
        ) { false }
        let second = PullRequestStore(
            github: GitHubClient(runner: runner), store: MetadataStore(file: root + "/state.json"),
        ) { false }
        async let one = first.queuedNumbers(repositoryPaths: sidebarFirst ? ["/repo", "/other"] : ["/repo"])
        var started = runner.started.stream.makeAsyncIterator()
        _ = await started.next()
        async let two = second.queuedNumbers(repositoryPaths: sidebarFirst ? ["/repo"] : ["/repo", "/other"])
        try await Task.sleep(for: .milliseconds(50))
        await runner.resume()

        #expect(await one["/repo"] == [7])
        #expect(await two["/repo"] == [7])
        #expect(await second.queuedNumbers(repositoryPaths: ["/repo", "/other"]) == ["/repo": [7], "/other": [7]])
        let queries = await runner.calls.flatMap { $0.filter { $0.hasPrefix("query=") } }
        #expect(queries.count == (sidebarFirst ? 1 : 2))
        for name in ["repo", "other"] {
            let count = queries.count { $0.contains("name: \"" + name + "\"") }
            #expect(count == 1)
        }
    }

    @MainActor
    @Test
    func `a cached queue never waits for another repository`() async throws {
        let root = try TestSupport.temporaryDirectory("cached-queue")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let runner = PausedRepositoryRunner()
        let metadata = MetadataStore(file: root + "/state.json")
        metadata.update { value in
            value.queuedCache["/repo"] = [8]
            value.fetchedAt["queue#/repo"] = Date()
        }
        let store = PullRequestStore(github: GitHubClient(runner: runner), store: metadata) { false }
        async let fetching = store.queuedNumbers(repositoryPaths: ["/other"])
        var started = runner.started.stream.makeAsyncIterator()
        _ = await started.next()
        var returned = false
        let cached = Task {
            let answer = await store.queuedNumbers(repositoryPaths: ["/repo"])
            returned = true
            return answer
        }
        for _ in 0 ..< 100 where returned == false {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(returned)
        await runner.resume()
        #expect(await cached.value == ["/repo": [8]])
        #expect(await fetching == ["/other": [7]])
        #expect(await runner.calls.count == 1)
    }
}

// MARK: - PausedRepositoryRunner

private actor PausedRepositoryRunner: ProcessRunner {
    // MARK: Internal

    let started: (stream: AsyncStream<Void>, continuation: AsyncStream<Void>.Continuation) = AsyncStream.makeStream()
    private(set) var calls: [[String]] = []

    func run(
        _ arguments: [String], workingDirectory: String?, environment _: [String: String], outputLimit _: Int?,
    ) async -> ProcessResult {
        if arguments.first == "git" {
            return ProcessResult(
                status: 0,
                standardOutput: "git@github.com:owner/" + URL(fileURLWithPath: workingDirectory ?? "/repo")
                    .lastPathComponent + ".git\n",
                standardError: "",
            )
        }
        calls.append(arguments)
        if released == false {
            await withCheckedContinuation { continuation in
                waiting.append(continuation)
                started.continuation.yield(())
            }
        }
        let output =
            if arguments.contains("repos/{owner}/{repo}/branches/main") {
                #"{"protected":true,"required":["test"]}"#
            } else if arguments.contains("repos/{owner}/{repo}/rules/branches/main") {
                "[]"
            } else if arguments.contains("label") {
                "bug\n"
            } else {
                """
                {"data":{"repository":{"mergeQueue":{"id":"queue"}},
                  "r0":{"mergeQueue":{"entries":{"nodes":[{"pullRequest":{"number":7}}]}}},
                  "r1":{"mergeQueue":{"entries":{"nodes":[{"pullRequest":{"number":7}}]}}}}}
                """
            }
        return ProcessResult(status: 0, standardOutput: output, standardError: "")
    }

    func resume() {
        released = true
        for continuation in waiting {
            continuation.resume()
        }
        waiting = []
    }

    // MARK: Private

    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var released = false
}
