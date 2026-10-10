@testable import AgentIDEData
import Testing

struct AutofixVerificationTests {
    @Test
    func `final verification does not accept a review missing from the fresh response`() async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixBots = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
            metadata.pullRequestAutomation[AutofixFixture.key]?.roundsStarted = 1
            metadata.pullRequestAutomation[AutofixFixture.key]?.recordBotRequest(.copilot, head: "head", date: nil)
        }
        await fixture.update { value in
            value.reviewEvents = [AutofixFixture.botReview(head: "head")]
            value.freshReviewEvents = []
        }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.isLoopRunning == true)
        #expect(await fixture.state.requestedBots.isEmpty)
    }

    @Test
    func `the last push requests and waits for a review of its new head`() async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixCI = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixBots = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.pushAutomatically = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
        }
        await fixture.update { $0.reviewEvents = [AutofixFixture.botReview(head: "head")] }
        let driver = await fixture.driver()
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        #expect(await fixture.state.requestedBots.isEmpty)
        await fixture.complete()
        await fixture.update { $0.signedCommit = "signed" }
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.pushedCommit == "signed")
        await fixture.update { $0.head = "signed"; $0.freshHead = "signed"; $0.checkConclusion = "SUCCESS" }
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        #expect(await fixture.state.requestedBots == [.copilot])
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.isLoopRunning == true)
        await fixture.update { $0.reviewEvents = [AutofixFixture.botReview(head: "signed", date: .distantFuture)] }
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.loopResult == .finished)
        #expect(await fixture.state.deliveries.count == 1)
    }

    @Test(arguments: ["SUCCESS", "FAILURE", "CANCELLED"])
    func `the last round waits for new required results before reporting its outcome`(conclusion: String) async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixCI = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.pushAutomatically = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
        }
        let driver = await fixture.driver()
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        await fixture.complete()
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        #expect(await fixture.state.pushes == ["fixed"])
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.isAutomatic == true)
        await fixture.update { $0.head = "fixed"; $0.freshHead = "fixed"; $0.checksComplete = false }
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.isLoopRunning == true)
        await fixture.update { $0.checksComplete = true; $0.checkConclusion = conclusion; $0.hasSession = false }
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        let state = try #require(fixture.store.load().pullRequestAutomation[AutofixFixture.key])
        #expect(state.isLoopRunning == false)
        #expect(state.loopResult == (conclusion == "SUCCESS" ? .finished : .failed))
        #expect(state.lastResult.hasPrefix(conclusion == "SUCCESS" ? "Success" : "Still failing"))
        #expect(await fixture.state.deliveries.count == 1)
    }

    @Test
    func `bot reviews are requested while required CI is still running`() async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixCI = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixBots = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
        }
        await fixture.update { $0.checksComplete = false }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        #expect(await fixture.state.requestedBots == [.copilot])
        #expect(await fixture.state.deliveries.isEmpty)
    }
}
