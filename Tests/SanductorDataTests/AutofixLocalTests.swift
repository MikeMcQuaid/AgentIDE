import Darwin
import Foundation
@testable import SanductorData
import SanductorDomain
import Testing

struct AutofixLocalTests {
    @Test(arguments: ["head", "fixed"])
    func `local findings resolve before GitHub and update the captured review`(commit: String) async throws {
        let fixture = try AutofixFixture()
        let review = LocalReview(reviewer: .codexCLI, snapshot: "diff", revision: "revision", threads: [
            AutofixFixture.thread("local"), AutofixFixture.thread("unfixed", comment: "unfixed"),
        ])
        let collection = LocalFeedbackCollection(
            id: "collection", revision: "revision", configuration: "tools", isPending: false, review: review,
        )
        fixture.store.update { metadata in
            metadata.localReviews["/worktree"] = review
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixLocalReviews = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixReviews = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.isAutomatic = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.collection = collection
        }
        await fixture.update { state in
            state.localReview = review
            state.localCollection = collection
            state.comments = [AutofixFixture.thread("remote", comment: "remote")]
            state.writers = ["human"]
        }
        let driver = await fixture.driver()
        let coordinator = AutofixCoordinator()
        await coordinator.refresh(store: fixture.store, driver: driver)
        await fixture.complete(addressed: ["local", "remote"], commit: commit)
        await fixture.update { $0.freshSummaryAvailable = false }
        await coordinator.refresh(store: fixture.store, driver: driver)
        let metadata = fixture.store.load()
        #expect(metadata.localReviews["/worktree"]?.threads.first?.isResolved == true)
        #expect(metadata.localReviews["/worktree"]?.threads.last?.isResolved == false)
        let pending = try #require(metadata.pullRequestAutomation[AutofixFixture.key])
        #expect(pending.collection?.review?.threads.first?.isResolved == true)
        #expect(pending.attempt != nil)
        await fixture.update { $0.freshSummaryAvailable = true }
        await coordinator.refresh(store: fixture.store, driver: driver)
        let completed = try #require(fixture.store.load().pullRequestAutomation[AutofixFixture.key])
        #expect(completed.resolutions["remote"]?.fixCommit == commit)
        #expect(completed.attempt == nil)
        #expect(await fixture.state.resolutions.isEmpty)
    }

    @Test(arguments: AgentKind.allCases)
    func `local reviews batch with CI and mark only addressed findings`(
        reviewer: AgentKind,
    ) async throws {
        let fixture = try AutofixFixture()
        let review = LocalReview(reviewer: reviewer, snapshot: "snapshot", revision: "revision", threads: [
            AutofixFixture.thread("fixed", context: "reviewed source"), AutofixFixture.thread("left", comment: "left"),
        ])
        var collection = LocalFeedbackCollection(id: "collection", revision: "revision", configuration: "tools")
        collection.review = review
        collection.isPending = false
        let captured = collection
        fixture.store.update { value in
            value.localReviews["/worktree"] = review
            value.pullRequestAutomation[AutofixFixture.key]?.isAutomatic = true
            value.pullRequestAutomation[AutofixFixture.key]?.autofixLocalReviews = true
            value.pullRequestAutomation[AutofixFixture.key]?.autofixCI = true
            value.pullRequestAutomation[AutofixFixture.key]?.collection = captured
        }
        await fixture.update { $0.localReview = review; $0.localCollection = captured }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        let prompt = try #require(await fixture.state.prompts.first)
        #expect(prompt.contains("test: FAILURE"))
        #expect(prompt.contains("Fix fixed"))
        await fixture.complete(addressed: ["fixed"])
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        let saved = try #require(fixture.store.load().localReviews["/worktree"])
        #expect(saved.threads.first?.isResolved == true)
        #expect(saved.threads.first?.codeContext == "reviewed source")
        #expect(saved.threads.last?.isResolved == false)
        #expect(await fixture.state.resolutions.isEmpty)
    }

    @Test
    func `an incomplete local review cannot be delivered`() async throws {
        let fixture = try AutofixFixture()
        let pending = LocalFeedbackCollection(id: "collection", revision: "revision", configuration: "tools")
        fixture.store.update { value in
            value.pullRequestAutomation[AutofixFixture.key]?.isAutomatic = true
            value.pullRequestAutomation[AutofixFixture.key]?.autofixLocalReviews = true
            value.pullRequestAutomation[AutofixFixture.key]?.collection = pending
        }
        await fixture.update { $0.localCollection = pending }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        #expect(await fixture.state.deliveries.isEmpty)
    }

    @Test
    func `result files cannot follow symlinks or block on a pipe`() throws {
        let directory = try TestSupport.temporaryDirectory("autofix-result")
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let result = directory + "/result.json"
        try #"{"attemptID":"attempt","head":"before","commit":"after","addressedThreadIDs":[]}"#
            .write(toFile: result, atomically: true, encoding: .utf8)
        #expect(try AutofixResult.read(path: result)?.commit == "after")
        try FileManager.default.createSymbolicLink(atPath: directory + "/link", withDestinationPath: result)
        #expect(throws: (any Error).self) { try AutofixResult.read(path: directory + "/link") }
        let fifo = directory + "/pipe"
        #expect(unsafe mkfifo(fifo, 0o600) == 0)
        #expect(throws: (any Error).self) { try AutofixResult.read(path: fifo) }
        #expect(try AutofixResult.read(path: directory + "/missing") == nil)
    }
}
