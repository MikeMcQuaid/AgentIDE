@testable import SanductorData
import SanductorDomain
import Testing

struct AutofixWatchingTests {
    @Test
    func `fixes stay local and later comments on the published head still trigger fixes`() async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixReviews = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
        }
        await fixture.update { value in
            value.comments = [AutofixFixture.thread("first")]
            value.writers = ["human"]
        }
        let coordinator = AutofixCoordinator()
        await coordinator.refresh(store: fixture.store, driver: fixture.driver())
        await fixture.complete(addressed: ["first"])
        await coordinator.refresh(store: fixture.store, driver: fixture.driver())
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.isAutomatic == true)
        await coordinator.refresh(store: fixture.store, driver: fixture.driver())
        #expect(await fixture.state.deliveries.count == 1)
        await fixture.update { $0.comments.append(AutofixFixture.thread("second", comment: "second")) }
        await coordinator.refresh(store: fixture.store, driver: fixture.driver())
        #expect(await fixture.state.deliveries.count == 2)
        #expect(await fixture.state.deliveries.last?.head == "fixed")
    }

    @Test
    func `optional jobs delay a batch of CI and human feedback`() async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixCI = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixReviews = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
        }
        await fixture.update { value in
            value.optionalComplete = false
            value.comments = [AutofixFixture.thread("review")]
            value.writers = ["human"]
        }
        let coordinator = AutofixCoordinator()
        await coordinator.refresh(store: fixture.store, driver: fixture.driver())
        #expect(await fixture.state.deliveries.isEmpty)
        await fixture.update { $0.optionalComplete = true }
        await coordinator.refresh(store: fixture.store, driver: fixture.driver())
        #expect(await fixture.state.deliveries.count == 1)
        #expect(await fixture.state.deliveries.last?.sources == [.checks, .reviews])
    }

    @Test
    func `watching bots never requests a new remote review`() async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixBots = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.isAutomatic = true
        }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.isAutomatic == true)
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.botRequests == nil)
    }

    @Test(arguments: ["human", "reader", "copilot-pull-request-reviewer", "coderabbitai"])
    func `pending reviews wait for either bot or verified writers`(reviewer: String) async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixCI = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixReviews = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixBots = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
        }
        await fixture.update { value in
            value.requestedReviewers = [reviewer]
            value.writers = ["human"]
        }
        let coordinator = AutofixCoordinator()
        await coordinator.refresh(store: fixture.store, driver: fixture.driver())
        #expect(await fixture.state.deliveries.count == (reviewer == "reader" ? 1 : 0))
        await fixture.update { $0.requestedReviewers = [] }
        await coordinator.refresh(store: fixture.store, driver: fixture.driver())
        #expect(await fixture.state.deliveries.count == 1)
    }

    @Test(arguments: [false, true])
    func `published feedback requires an ancestor even after log preparation`(duringPreparation: Bool) async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixCI = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
        }
        await fixture.update { value in
            value.localHead = "local"
            value.containsRemoteHead = duringPreparation
        }
        var driver = await fixture.driver()
        driver.prepare = { _, _, candidate in
            await fixture.update { $0.containsRemoteHead = false }
            return candidate.text
        }
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        #expect(await fixture.state.deliveries.isEmpty)
    }

    @Test(arguments: [false, true])
    func `human summary findings require freshly verified write access`(revoked: Bool) async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixReviews = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.isAutomatic = true
        }
        await fixture.update { value in
            value.writers = ["human"]
            value.freshWriters = revoked ? [] : ["human"]
            value.reviewEvents = [
                ReviewComment(
                    id: 1,
                    author: "human",
                    body: "Fix the regression",
                    kind: "CHANGES_REQUESTED",
                    nodeID: "review",
                    authorType: "User",
                    commit: "head",
                ),
            ]
        }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        #expect(await fixture.state.deliveries.count == (revoked ? 0 : 1))
        if revoked == false {
            #expect(await fixture.state.prompts.first?.contains("Fix the regression") == true)
        }
    }
}
