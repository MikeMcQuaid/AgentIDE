import Foundation
@testable import SanductorData
import SanductorDomain
import Testing

struct FeedbackStagesTests {
    // MARK: Internal

    @Test
    func `worktree loops finish locally when the review is clear`() async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.localWorktreePath = "/worktree"
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixLocalReviews = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.localRoundLimit = 3
            metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
        }
        await localReview(fixture, id: "first")
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        await fixture.complete(commit: "fixed")
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        await localReview(fixture, id: nil)
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        let state = try #require(fixture.store.load().pullRequestAutomation[AutofixFixture.key])
        #expect(state.isAutomatic == false)
        #expect(state.attempt == nil)
        #expect(state.lastResult == "Local review and fixes complete")
        #expect(await fixture.state.deliveries.count == 1)
    }

    @Test(arguments: PullRequestAutomation.localRoundLimits)
    func `only local reviews stop at their limit while GitHub keeps watching`(limit: Int) async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixLocalReviews = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixCI = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixReviews = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.localRoundLimit = limit
            metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
        }
        await fixture.update { value in
            value.checksComplete = false
            value.localHead = "unpublished"
            value.writers = ["human"]
        }
        await localReview(fixture, id: "1")
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        #expect(await fixture.state.deliveries.isEmpty)
        await fixture.update { $0.checksComplete = true }
        for index in 1 ... limit {
            await localReview(fixture, id: String(index))
            await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
            #expect(await fixture.state.deliveries.count == index)
            #expect(await fixture.state.deliveries.last?.sources
                == (index == 1 ? [.checks, .localReview] : [.localReview]))
            await fixture.complete(commit: "local-" + String(index))
            await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        }
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.localRoundsStarted == limit)
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.isAutomatic == true)
        await localReview(fixture, id: "over-limit")
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        #expect(await fixture.state.deliveries.count == limit)
        await fixture.update { $0.comments = [AutofixFixture.thread("remote")] }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        #expect(await fixture.state.deliveries.count == limit + 1)
        #expect(await fixture.state.deliveries.last?.sources == [.reviews])
    }

    // MARK: Private

    private func localReview(_ fixture: AutofixFixture, id: String?) async {
        let review = LocalReview(
            reviewer: .codexCLI,
            snapshot: "snapshot",
            revision: "revision",
            threads: id.map { [AutofixFixture.thread($0)] } ?? [],
        )
        var collection = LocalFeedbackCollection(id: id ?? "clear", revision: "revision", configuration: "reviewer")
        collection.review = review
        collection.isPending = false
        let finished = collection
        fixture.store.update { $0.pullRequestAutomation[AutofixFixture.key]?.collection = finished }
        await fixture.update { $0.localReview = review; $0.localCollection = finished }
    }
}
