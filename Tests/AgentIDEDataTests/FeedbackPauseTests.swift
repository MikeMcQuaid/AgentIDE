@testable import AgentIDEData
import AgentIDEDomain
import Testing

struct FeedbackPauseTests {
    // MARK: Internal

    @Test(arguments: [true, false])
    func `continuing preserves the shared remote budget and push opt-in`(automaticPush: Bool) async throws {
        let fixture = try await pausedFixture(automaticPush: automaticPush)
        let events = fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.handledEvents
        fixture.store.update { $0.pullRequestAutomation[AutofixFixture.key]?.continueToGitHub() }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        #expect(await fixture.state.pushes == (automaticPush ? ["fixed"] : []))
        #expect(await fixture.state.deliveries.count == 1)
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.handledEvents == events)
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.roundsStarted == 0)
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.isPausedForReview == false)
        await fixture.update { $0.head = "fixed"; $0.freshHead = "fixed" }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        #expect(await fixture.state.deliveries.last?.sources == [.checks, .reviews])
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.roundsStarted == 1)
        await fixture.complete(commit: "remote-fix")
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.isAutomatic == false)
    }

    @Test(arguments: [true, false])
    func `continuing cannot push a changed local or remote head`(local: Bool) async throws {
        let fixture = try await pausedFixture(automaticPush: true)
        await fixture.update { value in
            if local {
                value.localHead = "changed"
            } else {
                value.head = "changed"
                value.freshHead = "changed"
            }
        }
        fixture.store.update { $0.pullRequestAutomation[AutofixFixture.key]?.continueToGitHub() }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        #expect(await fixture.state.pushes.isEmpty)
        #expect(await fixture.state.deliveries.count == 1)
    }

    @Test
    func `starting another local cycle preserves claims and requests fresh feedback`() async throws {
        let fixture = try await pausedFixture(automaticPush: true)
        let events = fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.handledEvents
        fixture.store.update { $0.pullRequestAutomation[AutofixFixture.key]?.startLoop() }
        let state = try #require(fixture.store.load().pullRequestAutomation[AutofixFixture.key])
        #expect(state.isPausedForReview == false)
        #expect(state.isLocalStage)
        #expect(state.localRoundsStarted == 0)
        #expect(state.repeatLocalReview)
        #expect(state.collection == nil)
        #expect(state.attempt == nil)
        #expect(state.handledEvents == events)
    }

    // MARK: Private

    private func pausedFixture(automaticPush: Bool) async throws -> AutofixFixture {
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
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixReviews = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.pushAutomatically = automaticPush
            metadata.pullRequestAutomation[AutofixFixture.key]?.collection = finished
            metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
        }
        await fixture.update { value in
            value.localReview = review
            value.localCollection = finished
            value.comments = [AutofixFixture.thread("remote")]
            value.writers = ["human"]
        }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        await fixture.complete()
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        return fixture
    }
}
