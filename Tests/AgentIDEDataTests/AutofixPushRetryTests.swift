@testable import AgentIDEData
import Testing

struct AutofixPushRetryTests {
    // MARK: Internal

    @Test
    func `retry after successful signing uses the signed tip`() async throws {
        let fixture = try await failedPush(signedCommit: "signed")
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.failedPush?.commit == "signed")
        fixture.store.update { $0.pullRequestAutomation[AutofixFixture.key]?.retryPush() }
        await fixture.update { $0.failPush = false }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        #expect(await fixture.state.pushes == ["fixed", "signed"])
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.pushedCommit == "signed")
    }

    @Test
    func `a failed push waits for a click then retries without another fix round`() async throws {
        let fixture = try await failedPush()
        let failed = try #require(fixture.store.load().pullRequestAutomation[AutofixFixture.key])
        #expect(failed.failedPush?.commit == "fixed")
        #expect(failed.loopResult == .failed)
        #expect(failed.isLoopRunning == false)
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        #expect(await fixture.state.pushes == ["fixed"])
        fixture.store.update { $0.pullRequestAutomation[AutofixFixture.key]?.retryPush() }
        await fixture.update { $0.failPush = false; $0.signedCommit = "signed" }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        let pushed = try #require(fixture.store.load().pullRequestAutomation[AutofixFixture.key])
        #expect(await fixture.state.pushes == ["fixed", "fixed"])
        #expect(await fixture.state.deliveries.count == 1)
        #expect(pushed.roundsStarted == 1)
        #expect(pushed.pushedCommit == "signed")
        #expect(pushed.failedPush == nil)
        #expect(pushed.isAutomatic)
        #expect(pushed.handledEvents == failed.handledEvents)
        fixture.store.update { $0.pullRequestAutomation[AutofixFixture.key]?.retryPush() }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        #expect(await fixture.state.pushes.count == 2)
    }

    @Test(arguments: ["local", "remote", "dirty", "busy", "session"])
    func `retry rechecks the branch state before pushing`(changed: String) async throws {
        let fixture = try await failedPush()
        fixture.store.update { $0.pullRequestAutomation[AutofixFixture.key]?.retryPush() }
        await fixture.update { state in
            switch changed {
            case "local":
                state.localHead = "changed"

            case "remote":
                state.freshHead = "changed"

            case "dirty":
                state.isDirty = true

            case "busy":
                state.activity = .working

            default:
                state.hasSession = false
            }
        }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        #expect(await fixture.state.pushes == ["fixed"])
        #expect(await fixture.state.deliveries.count == 1)
    }

    @Test
    func `a push already confirmed by GitHub is not sent again`() async throws {
        let fixture = try await failedPush()
        fixture.store.update { $0.pullRequestAutomation[AutofixFixture.key]?.retryPush() }
        await fixture.update { $0.head = "fixed"; $0.freshHead = "fixed" }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        #expect(await fixture.state.pushes == ["fixed"])
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.failedPush == nil)
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.isAutomatic == true)
    }

    @Test(arguments: ["stop", "start", "launch"])
    func `resetting the loop cancels pending push retries`(action: String) async throws {
        let fixture = try await failedPush()
        fixture.store.update { $0.pullRequestAutomation[AutofixFixture.key]?.retryPush() }
        switch action {
        case "stop":
            fixture.store.update { $0.pullRequestAutomation[AutofixFixture.key]?.stopLoop() }

        case "start":
            fixture.store.update { $0.pullRequestAutomation[AutofixFixture.key]?.startLoop() }

        default:
            fixture.store.resetFeedbackLoops()
        }
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.failedPush == nil)
    }

    @Test(arguments: ["fixed", "signed", "manual-follow-up"])
    func `a manual push clears failure without clicking retry`(pushed: String) async throws {
        let fixture = try await failedPush()
        let previous = try #require(fixture.store.load().pullRequestAutomation[AutofixFixture.key])
        await fixture.update { $0.localHead = pushed; $0.head = pushed; $0.freshHead = pushed }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        let current = try #require(fixture.store.load().pullRequestAutomation[AutofixFixture.key])
        #expect(current.failedPush == nil)
        #expect(current.isAutomatic)
        #expect(current.roundsStarted == previous.roundsStarted)
        #expect(current.handledEvents == previous.handledEvents)
        #expect(await fixture.state.pushes == ["fixed"])
    }

    @Test
    func `manual signing can be retried with the current equivalent tip`() async throws {
        let fixture = try await failedPush()
        fixture.store.update { $0.pullRequestAutomation[AutofixFixture.key]?.retryPush() }
        await fixture.update { $0.localHead = "signed-manually"; $0.failPush = false }
        var driver = await fixture.driver()
        driver.sameTree = { _, original, current in original == "fixed" && current == "signed-manually" }
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        #expect(await fixture.state.pushes == ["fixed", "signed-manually"])
        #expect(await fixture.state.deliveries.count == 1)
    }

    @Test
    func `retry after manual code changes revalidates without pushing stale results`() async throws {
        let fixture = try await failedPush()
        fixture.store.update { $0.pullRequestAutomation[AutofixFixture.key]?.retryPush() }
        await fixture.update { $0.localHead = "manual-commit"; $0.failPush = false }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        let current = try #require(fixture.store.load().pullRequestAutomation[AutofixFixture.key])
        #expect(current.failedPush == nil)
        #expect(current.isPreparingExistingWork)
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        #expect(await fixture.state.deliveries.last?.sources == [.existingWork])
        #expect(await fixture.state.pushes == ["fixed"])
    }

    // MARK: Private

    private func failedPush(signedCommit: String? = nil) async throws -> AutofixFixture {
        let fixture = try AutofixFixture()
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixCI = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.pushAutomatically = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
        }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        await fixture.complete()
        await fixture.update { $0.failPush = true; $0.signedCommit = signedCommit }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        return fixture
    }
}
