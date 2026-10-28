import Foundation
@testable import SanductorData
import Testing

extension PullRequestStoreTests {
    @Test(arguments: [false, true])
    func `simultaneous panes share a GitHub read`(summary: Bool) async throws {
        let root = try TestSupport.temporaryDirectory("shared-pr-read")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let runner = PausedPullRequestRunner()
        let first = PullRequestStore(
            github: GitHubClient(runner: runner), store: MetadataStore(file: root + "/state.json"),
        ) { false }
        let second = PullRequestStore(
            github: GitHubClient(runner: runner), store: MetadataStore(file: root + "/state.json"),
        ) { false }
        let read: @Sendable (PullRequestStore) async throws -> [Int] = { store in
            if summary {
                return try await store.summary(repositoryPath: "/repo", number: 7).map { [$0.number] } ?? []
            }
            return try await store.listing(repositoryPath: "/repo", scope: .branch("work")).map(\.number)
        }
        async let one = read(first)
        async let two = read(second)
        var started = runner.started.stream.makeAsyncIterator()
        _ = await started.next()
        try await Task.sleep(for: .milliseconds(50))
        await runner.resume()

        #expect(try await one == [7])
        #expect(try await two == [7])
        #expect(await runner.calls == 1)
    }
}

// MARK: - PausedPullRequestRunner

private actor PausedPullRequestRunner: ProcessRunner {
    // MARK: Internal

    let started: (stream: AsyncStream<Void>, continuation: AsyncStream<Void>.Continuation) = AsyncStream.makeStream()
    private(set) var calls = 0

    func run(
        _ arguments: [String], workingDirectory: String?, environment: [String: String], outputLimit: Int?,
    ) async -> ProcessResult {
        if arguments.contains("view") || arguments.contains("--include") {
            calls += 1
            if released == false {
                await withCheckedContinuation { continuation in
                    waiting.append(continuation)
                    started.continuation.yield(())
                }
            }
        }
        return runner.run(
            arguments, workingDirectory: workingDirectory, environment: environment, outputLimit: outputLimit,
        )
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
    private let runner: CountingRunner = .init()
}
