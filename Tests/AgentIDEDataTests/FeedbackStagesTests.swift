@testable import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

struct FeedbackStagesTests {
    // MARK: Internal

    @Test
    func `worktree loops finish locally even with a saved push opt-in`() async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.localWorktreePath = "/worktree"
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixLocalReviews = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.pushAutomatically = true
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
        #expect(await fixture.state.pushes.isEmpty)
    }

    @Test(arguments: PullRequestAutomation.roundLimits)
    func `the local round limit pushes committed fixes before starting remote rounds`(limit: Int) async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixLocalReviews = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixCI = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixReviews = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.pushAutomatically = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.localRoundLimit = limit
            metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
        }
        await fixture.update { value in
            value.checksComplete = false
            value.localHead = "unpublished"
            value.comments = [AutofixFixture.thread("remote")]
            value.writers = ["human"]
        }
        for index in 1 ... limit {
            await localReview(fixture, id: String(index))
            await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
            #expect(await fixture.state.deliveries.count == index)
            #expect(await fixture.state.deliveries.last?.sources == [.localReview])
            #expect(await fixture.state.pushes.isEmpty)
            await fixture.complete(commit: "local-" + String(index))
            await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        }
        #expect(await fixture.state.pushes == ["local-" + String(limit)])
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.localRoundsStarted == limit)
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.roundsStarted == 0)
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.isAutomatic == true)
        await fixture.update { $0.head = "local-" + String(limit); $0.freshHead = $0.head }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        #expect(await fixture.state.deliveries.count == limit)
        await fixture.update { $0.checksComplete = true }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        #expect(await fixture.state.deliveries.count == limit + 1)
        #expect(await fixture.state.deliveries.last?.sources == [.checks, .reviews])
    }

    @Test(arguments: [true, false])
    func `a clear local review completes early and preserves deferred pushing across reloads`(
        automaticPush: Bool,
    ) async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixLocalReviews = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixCI = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.pushAutomatically = automaticPush
            metadata.pullRequestAutomation[AutofixFixture.key]?.localRoundLimit = 3
            metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
        }
        await localReview(fixture, id: "first")
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        await fixture.complete(commit: "head")
        await fixture.update { $0.isDirty = true }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        #expect(await fixture.state.deliveries.count == 2)
        #expect(await fixture.state.pushes.isEmpty)
        await fixture.complete(commit: "fixed")
        await fixture.update { $0.isDirty = false }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        let reloaded = try JSONDecoder().decode(AppMetadata.self, from: JSONEncoder().encode(fixture.store.load()))
        fixture.store.update { $0 = reloaded }
        await localReview(fixture, id: nil)
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        #expect(await fixture.state.pushes == (automaticPush ? ["fixed"] : []))
        #expect(await fixture.state.deliveries.count == 2)
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.isLocalStage == false)
        await fixture.update { $0.head = "fixed"; $0.freshHead = "fixed" }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        #expect(await fixture.state.deliveries.last?.sources == [.checks])
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
