@testable import AgentIDEData
import AgentIDEDomain
import Testing

struct FeedbackLoopTests {
    @Test(arguments: [true, false])
    func `remote feedback waits for a fixing session without running a local review`(checks: Bool) async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { value in
            value.pullRequestAutomation[AutofixFixture.key]?.autofixCI = checks
            value.pullRequestAutomation[AutofixFixture.key]?.autofixReviews = checks == false
            value.pullRequestAutomation[AutofixFixture.key]?.startLoop()
        }
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.activityStatus
            == "Starting feedback loop")
        await fixture.update { value in
            value.hasSession = false
            value.comments = [AutofixFixture.thread("remote")]
            value.writers = ["human"]
        }
        var driver = await fixture.driver()
        driver.collect = { _, _, _ in
            Issue.record("Local review must not run when its source is disabled")
            return nil
        }
        driver.localReview = { _ in
            Issue.record("Local findings must not be included when their source is disabled")
            return nil
        }
        let coordinator = AutofixCoordinator()
        await coordinator.refresh(store: fixture.store, driver: driver)
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.activityStatus
            == "Waiting for an agent session on this branch to apply fixes")
        #expect(await fixture.state.deliveries.isEmpty)
        await fixture.update { $0.hasSession = true; $0.activity = .working }
        await coordinator.refresh(store: fixture.store, driver: driver)
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.activityStatus
            == "Your agent is working on something else. Autofix will wait until it finishes.")
        #expect(await fixture.state.deliveries.isEmpty)
        await fixture.update { $0.activity = .done }
        await coordinator.refresh(store: fixture.store, driver: driver)
        #expect(await fixture.state.deliveries.count == 1)
        #expect(await fixture.state.deliveries.first?.sources == (checks ? [.checks] : [.reviews]))
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.localRoundsStarted == 0)
    }

    @Test
    func `selected sources are inert until automatic mode is enabled`() async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { $0.pullRequestAutomation[AutofixFixture.key]?.autofixCI = true }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        #expect(await fixture.state.deliveries.isEmpty)
    }

    @Test
    func `CI and trusted reviews share one round and one prompt`() async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { value in
            value.pullRequestAutomation[AutofixFixture.key]?.isAutomatic = true
            value.pullRequestAutomation[AutofixFixture.key]?.autofixCI = true
            value.pullRequestAutomation[AutofixFixture.key]?.autofixReviews = true
        }
        await fixture.update { $0.comments = [AutofixFixture.thread("review")]; $0.writers = ["human"] }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        let prompt = try #require(await fixture.state.prompts.first)
        #expect(prompt.contains("test"))
        #expect(prompt.contains("review"))
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.roundsStarted == 1)
    }

    @Test
    func `only the selected Copilot bot bypasses human permissions`() async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { value in
            value.pullRequestAutomation[AutofixFixture.key]?.isAutomatic = true
            value.pullRequestAutomation[AutofixFixture.key]?.autofixCopilot = true
        }
        await fixture.update { value in
            value.reviewEvents = [AutofixFixture.botReview(head: "head")]
            value.comments = [
                AutofixFixture.thread("copilot", comment: "copilot", author: GitHubClient.copilotReviewer, type: "Bot"),
                AutofixFixture.thread("unknown-bot", comment: "bot", author: "bot", type: "Bot"),
                AutofixFixture.thread("private-repo-reader", comment: "reader"),
            ]
        }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        let prompt = try #require(await fixture.state.prompts.first)
        #expect(prompt.contains("Fix copilot"))
        #expect(prompt.contains("unknown-bot") == false)
        #expect(prompt.contains("private-repo-reader") == false)
    }

    @Test(arguments: [1, 2, 3])
    func `round budget survives coordinator restarts`(limit: Int) async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { value in
            value.pullRequestAutomation[AutofixFixture.key]?.isAutomatic = true
            value.pullRequestAutomation[AutofixFixture.key]?.autofixReviews = true
            value.pullRequestAutomation[AutofixFixture.key]?.roundLimit = limit
        }
        for index in 0 ... limit {
            await fixture.update { value in
                value.comments = [AutofixFixture.thread("thread", comment: String(index))]
                value.writers = ["human"]
                value.head = String(index); value.freshHead = String(index); value.localHead = String(index)
            }
            await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
            await fixture.complete()
            await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        }
        #expect(await fixture.state.deliveries.count == limit)
    }
}
