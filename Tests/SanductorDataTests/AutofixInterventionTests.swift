@testable import SanductorData
import Testing

struct AutofixInterventionTests {
    @Test
    func `watching without a manual push does not resend completed fixes`() async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixCI = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
        }
        let driver = await fixture.driver()
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        await fixture.complete()
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        #expect(await fixture.state.deliveries.count == 1)
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.isLoopRunning == true)
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.pending.contains("Watching") == true)
        await fixture.update { $0.head = "fixed"; $0.freshHead = "fixed"; $0.checkConclusion = "SUCCESS" }
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.isAutomatic == true)
        #expect(await fixture.state.deliveries.count == 1)
    }

    @Test(arguments: [false, true])
    func `signing and manual pushes retain addressed threads without another push`(pushed: Bool) async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixReviews = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
        }
        await fixture.update { $0.comments = [AutofixFixture.thread("thread")]; $0.writers = ["human"] }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        await fixture.complete(addressed: ["thread"])
        await fixture.update { state in
            state.localHead = "signed"
            if pushed {
                state.head = "signed"; state.freshHead = "signed"
            }
        }
        var driver = await fixture.driver()
        driver.sameTree = { _, original, current in original == "fixed" && current == "signed" }
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.attempt == nil)
        if pushed {
            await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
            #expect(await fixture.state.resolutions == ["thread"])
        }
        #expect(await fixture.state.deliveries.count == 1)
    }

    @Test
    func `manual code edits after a result get validated without resetting rounds or claims`() async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixCI = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
        }
        let driver = await fixture.driver()
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        await fixture.complete()
        await fixture.update { $0.localHead = "manual-amend" }
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        #expect(await fixture.state.deliveries.count == 1)
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.handledEvents.contains("run:1") == true)
        await fixture.complete(commit: "manual-amend")
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
    }

    @Test(arguments: [false, true])
    func `manual changes between rounds are checked before gathering feedback`(
        dirty: Bool,
    ) async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixCI = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
            metadata.pullRequestAutomation[AutofixFixture.key]?.preparingExistingWork = false
        }
        await fixture.update { $0.localHead = dirty ? "head" : "manual-commit"; $0.isDirty = dirty }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.isPreparingExistingWork
            == dirty)
    }
}
