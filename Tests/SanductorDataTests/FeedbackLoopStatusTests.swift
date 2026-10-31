import Foundation
@testable import SanductorData
import Testing

struct FeedbackLoopStatusTests {
    @Test
    func `source selection and manual review results do not start a loop`() {
        var state = PullRequestAutomation(repositoryPath: "/repo", number: 1, url: "pr")
        state.autofixLocalReviews = true
        state.localRoundLimit = 3
        state.lastResult = "Local findings are ready"
        #expect(state.loopStatus == "Not started")
        #expect(state.isLoopRunning == false)
        state.startLoop()
        #expect(state.loopStatus == "Running")
        #expect(state.lastResult.isEmpty)
        state.stopLoop()
        #expect(state.loopStatus == "Stopped")
        #expect(state.isLoopRunning == false)
    }

    @Test
    func `the loop keeps watching after local fixes and a manual push`() async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { value in
            value.pullRequestAutomation[AutofixFixture.key]?.autofixCI = true
            value.pullRequestAutomation[AutofixFixture.key]?.startLoop()
        }
        let coordinator = AutofixCoordinator()
        await coordinator.refresh(store: fixture.store, driver: fixture.driver())
        var state = try #require(fixture.store.load().pullRequestAutomation[AutofixFixture.key])
        #expect(state.loopStatus == "Running")
        #expect(state.activityStatus == "Fix-and-commit prompt sent; follow progress in the agent pane")
        await fixture.complete()
        await coordinator.refresh(store: fixture.store, driver: fixture.driver())
        state = try #require(fixture.store.load().pullRequestAutomation[AutofixFixture.key])
        #expect(state.isAutomatic == true)
        #expect(state.isLoopRunning)
        #expect(state.nextTrigger.contains("Push manually"))
        #expect(state.activityLog?.contains { $0.message == "Finished feedback loop" } == false)
        #expect(state.activityLog?.contains { $0.message == "Stopped feedback loop" } == false)
        await fixture.update { $0.head = "fixed"; $0.freshHead = "fixed"; $0.checkConclusion = "SUCCESS" }
        await coordinator.refresh(store: fixture.store, driver: fixture.driver())
        let restarted = try JSONDecoder().decode(AppMetadata.self, from: JSONEncoder().encode(fixture.store.load()))
        state = try #require(restarted.pullRequestAutomation[AutofixFixture.key])
        #expect(state.isLoopRunning)
        #expect(state.loopStatus == "Running")
        #expect(state.activityLog?.contains { $0.message == "Finished feedback loop" } == false)
        state.startLoop()
        state.stopLoop()
        #expect(state.loopStatus == "Stopped")
        #expect(state.isLoopRunning == false)
    }
}
