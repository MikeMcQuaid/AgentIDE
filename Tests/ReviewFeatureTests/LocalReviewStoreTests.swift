import AgentIDEData
import AgentIDEDomain
@testable import ReviewFeature
import Testing

@MainActor
struct LocalReviewStoreTests {
    // MARK: Internal

    @Test(arguments: [false, true])
    func `switching worktrees retains running reviews and their outcomes`(fails: Bool) async {
        let runner = Runner()
        let store = LocalReviewStore(makeModel: runner.model)
        var arrivals = runner.started.stream.makeAsyncIterator()
        var displayed = store.model(worktreePath: "/first")
        displayed.reviewInstructions = "Check the first worktree's security changes."
        let first = Task { [model = displayed] in await model.start(files: []) }
        #expect(await arrivals.next() == "/first")
        displayed = store.model(worktreePath: "/second")
        #expect(displayed.isRunning == false)
        let second = Task { [model = displayed] in await model.start(files: []) }
        #expect(await arrivals.next() == "/second")
        displayed = store.model(worktreePath: "/first")
        #expect(displayed.isRunning)
        #expect(displayed.reviewInstructions == "Check the first worktree's security changes.")
        await displayed.start(files: [])
        #expect(runner.calls == ["/first", "/second"])
        displayed = store.model(worktreePath: "/second")
        runner.finish(worktreePath: "/first", fails: fails)
        await first.value
        #expect(displayed.isRunning)
        #expect(displayed.review == nil)
        let returned = store.model(worktreePath: "/first")
        #expect(returned.isRunning == false)
        #expect((returned.error != nil) == fails)
        #expect((returned.review != nil) == (fails == false))
        #expect(returned.review == runner.saved["/first"])
        runner.finish(worktreePath: "/second", fails: false)
        await second.value
        #expect(displayed.isRunning == false)
        #expect(displayed.review == runner.saved["/second"])
        #expect(displayed.review?.revision == "/second")
    }

    // MARK: Private

    private final class Runner {
        // MARK: Lifecycle

        deinit {
            started.continuation.finish()
        }

        // MARK: Internal

        var calls: [String] = []
        var saved: [String: LocalReview] = [:]
        let started: (stream: AsyncStream<String>, continuation: AsyncStream<String>.Continuation) =
            AsyncStream.makeStream()
        var pending: [String: CheckedContinuation<LocalReview, any Error>] = [:]

        func model(worktreePath: String) -> LocalReviewModel {
            LocalReviewModel(
                review: saved[worktreePath],
                reviewer: .codexCLI,
                run: { [self] _, _, _ in
                    calls.append(worktreePath)
                    guard pending[worktreePath] == nil else {
                        throw CancellationError()
                    }

                    return try await withCheckedThrowingContinuation { continuation in
                        pending[worktreePath] = continuation
                        started.continuation.yield(worktreePath)
                    }
                },
                revision: { worktreePath },
                save: { self.saved[worktreePath] = $0 },
            )
        }

        func finish(worktreePath: String, fails: Bool) {
            let continuation = pending.removeValue(forKey: worktreePath)
            #expect(continuation != nil)
            if fails {
                continuation?.resume(throwing: CancellationError())
            } else {
                continuation?.resume(returning: LocalReview(
                    reviewer: .codexCLI,
                    snapshot: LocalReviewInput.fingerprint(LocalReviewInput.snapshot(files: [])),
                    revision: worktreePath,
                    threads: [],
                ))
            }
        }
    }
}
