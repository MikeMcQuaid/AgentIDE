@testable import AgentIDEData
import AgentIDEDomain
import Testing

struct FeedbackTransitionTests {
    // MARK: Internal

    @Test(arguments: [true, false])
    func `local completion respects the shared push opt-in`(automaticPush: Bool) async throws {
        let fixture = try await localFixture(automaticPush: automaticPush)
        await fixture.complete()
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        #expect(await fixture.state.pushes == (automaticPush ? ["fixed"] : []))
        #expect(await fixture.state.deliveries.count == 1)
        await fixture.update { $0.head = "fixed"; $0.freshHead = "fixed" }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        #expect(await fixture.state.deliveries.last?.sources == [.checks])
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.roundsStarted == 1)
    }

    @Test(arguments: [true, false])
    func `local completion cannot push a changed local or remote head`(local: Bool) async throws {
        let fixture = try await localFixture(automaticPush: true)
        await fixture.complete()
        await fixture.update { value in
            if local {
                value.localHead = "changed"
            } else {
                value.head = "changed"; value.freshHead = "changed"
            }
        }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        #expect(await fixture.state.pushes.isEmpty)
        #expect(await fixture.state.deliveries.count == 1)
    }

    @Test
    func `starting another local cycle preserves claims and requests fresh feedback`() async throws {
        let fixture = try await localFixture(automaticPush: false)
        await fixture.complete()
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        let events = fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.handledEvents
        fixture.store.update { $0.pullRequestAutomation[AutofixFixture.key]?.startLoop() }
        let state = try #require(fixture.store.load().pullRequestAutomation[AutofixFixture.key])
        #expect(state.isLocalStage)
        #expect(state.localRoundsStarted == 0)
        #expect(state.repeatLocalReview)
        #expect(state.collection == nil)
        #expect(state.attempt == nil)
        #expect(state.handledEvents == events)
    }

    // MARK: Private

    private func localFixture(automaticPush: Bool) async throws -> AutofixFixture {
        let fixture = try AutofixFixture()
        let review = LocalReview(reviewer: .codexCLI, snapshot: "diff", revision: "revision", threads: [
            AutofixFixture.thread("local"),
        ])
        var collection = LocalFeedbackCollection(id: "local", revision: "revision", configuration: "codex")
        collection.review = review
        collection.isPending = false
        let finished = collection
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixLocalReviews = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixCI = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.pushAutomatically = automaticPush
            metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
        }
        await fixture.update { $0.localReview = review; $0.localCollection = finished }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        return fixture
    }
}
