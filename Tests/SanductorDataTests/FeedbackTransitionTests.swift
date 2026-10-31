@testable import SanductorData
import SanductorDomain
import Testing

struct FeedbackTransitionTests {
    // MARK: Internal

    @Test
    func `local and remote feedback are committed together`() async throws {
        let fixture = try await localFixture()
        await fixture.complete()
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        #expect(await fixture.state.deliveries.count == 1)
        await fixture.update { $0.head = "fixed"; $0.freshHead = "fixed" }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        #expect(await fixture.state.deliveries.last?.sources == [.checks, .localReview])
    }

    @Test(arguments: [true, false])
    func `local completion cannot push a changed local or remote head`(local: Bool) async throws {
        let fixture = try await localFixture()
        await fixture.complete()
        await fixture.update { value in
            if local {
                value.localHead = "changed"
            } else {
                value.head = "changed"; value.freshHead = "changed"
            }
        }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        #expect(await fixture.state.deliveries.count == 1)
    }

    @Test
    func `starting another local cycle preserves claims and first checks existing feedback`() async throws {
        let fixture = try await localFixture()
        await fixture.complete()
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        let events = fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.handledEvents
        fixture.store.update { $0.pullRequestAutomation[AutofixFixture.key]?.startLoop() }
        let state = try #require(fixture.store.load().pullRequestAutomation[AutofixFixture.key])
        #expect(state.isLocalStage)
        #expect(state.localRoundsStarted == 0)
        #expect(state.repeatLocalReview == false)
        #expect(state.collection == nil)
        #expect(state.attempt == nil)
        #expect(state.handledEvents == events)
    }

    // MARK: Private

    private func localFixture() async throws -> AutofixFixture {
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
            metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
        }
        await fixture.update { $0.localReview = review; $0.localCollection = finished }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        return fixture
    }
}
