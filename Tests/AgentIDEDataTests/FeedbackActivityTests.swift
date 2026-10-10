@testable import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

struct FeedbackActivityTests {
    @Test
    func `launch resets loop progress but preserves preferences and side-effect claims`() async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { value in
            value.pullRequestAutomation[AutofixFixture.key]?.autofixCI = true
            value.pullRequestAutomation[AutofixFixture.key]?.startLoop()
            value.pullRequestAutomation[AutofixFixture.key]?.resolutions["thread"] = PendingThreadResolution(
                head: "head", commentID: "comment",
            )
        }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        var expected = try #require(fixture.store.load().pullRequestAutomation[AutofixFixture.key])
        #expect(expected.attempt != nil)
        #expect(expected.activityLog?.isEmpty == false)
        expected.activityLog = []
        expected.isAutomatic = false
        expected.attempt = nil
        expected.roundsStarted = 0
        expected.localRounds = LocalAutofixRounds(limit: expected.localRoundLimit)
        expected.repeatLocalReview = true
        expected.pending = ""
        expected.lastResult = ""
        expected.loopResult = nil
        fixture.store.resetFeedbackLoops()
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key] == expected)
    }

    @Test
    func `starting and stopping a loop clear old activity without forgetting handled feedback`() throws {
        let fixture = try AutofixFixture()
        fixture.store.update { value in
            value.pullRequestAutomation[AutofixFixture.key]?.lastResult
                = "Choose a non-empty diff smaller than 256 KiB for local review."
            value.pullRequestAutomation[AutofixFixture.key]?.handledEvents = ["previous-run"]
        }
        fixture.store.update { value in
            value.pullRequestAutomation[AutofixFixture.key]?.autofixCI = true
            value.pullRequestAutomation[AutofixFixture.key]?.startLoop()
        }
        let state = try #require(fixture.store.load().pullRequestAutomation[AutofixFixture.key])
        #expect(state.lastResult.isEmpty)
        #expect(state.activityLog?.contains { $0.message.contains("256 KiB") } == false)
        #expect(state.handledEvents == ["previous-run"])
        fixture.store.update { $0.pullRequestAutomation[AutofixFixture.key]?.stopLoop() }
        let stopped = try #require(fixture.store.load().pullRequestAutomation[AutofixFixture.key])
        #expect(stopped.activityLog?.map(\.message) == ["Stopped feedback loop"])
        #expect(stopped.handledEvents == ["previous-run"])
    }

    @Test
    func `local activity describes local fixes without remote transitions`() {
        var state = PullRequestAutomation(repositoryPath: "/repo", number: 0, url: "local:/worktree")
        state.localWorktreePath = "/worktree"
        state.autofixLocalReviews = true
        state.startLoop()
        #expect(state.nextTrigger.contains("GitHub") == false)
        state.isAutomatic = false
        #expect(state.nextTrigger.contains("GitHub") == false)
        #expect(state.nextTrigger.contains("Start loop"))
    }

    @Test(arguments: [true, false])
    func `missing CI results wait with a count or an unknown status`(unknown: Bool) async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { $0.pullRequestAutomation[AutofixFixture.key]?.autofixCI = true }
        let state = try #require(fixture.store.load().pullRequestAutomation[AutofixFixture.key])
        let summary = PullRequestSummary(
            number: 1,
            title: "Change",
            url: AutofixFixture.key,
            headBranch: "feature",
            mergeable: "",
            reviewDecision: "",
            checks: "",
            headCommit: "head",
            autofixChecks: unknown ? nil : AutofixChecks(required: ["test", "build"], results: []),
        )
        let driver = await fixture.driver()
        let target = try #require(await driver.target(state, summary))
        let ready = try await AutofixCoordinator().feedbackReady(
            state,
            summary: summary,
            target: target,
            context: AutofixContext(key: AutofixFixture.key, store: fixture.store, driver: driver),
        )
        #expect(ready == false)
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.pending == (unknown
                ? "Waiting for required CI results" : "Waiting for 2 required CI jobs"))
    }

    @Test
    func `wait transitions survive restart without growing on unchanged refreshes`() async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { value in
            value.pullRequestAutomation[AutofixFixture.key]?.autofixCI = true
            value.pullRequestAutomation[AutofixFixture.key]?.startLoop()
        }
        await fixture.update { $0.checksComplete = false }
        let coordinator = AutofixCoordinator()
        await coordinator.refresh(store: fixture.store, driver: fixture.driver())
        let log = fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.activityLog
        #expect(log?.contains { $0.message.contains("Started") } == true)
        #expect(log?.last?.message == "GitHub round 1/1 · Waiting for 1 required CI job")
        await coordinator.refresh(store: fixture.store, driver: fixture.driver())
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.activityLog == log)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restarted = try decoder.decode(
            AppMetadata.self, from: Data(contentsOf: URL(fileURLWithPath: fixture.directory + "/state.json")),
        )
        #expect(restarted.pullRequestAutomation[AutofixFixture.key]?.activityLog?.map(\.message) == log?.map(\.message))
        await fixture.update { $0.checksComplete = true }
        await coordinator.refresh(store: fixture.store, driver: fixture.driver())
        let delivered = fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.activityLog
        #expect(delivered?.contains { $0.message.contains("Trigger:") && $0.message.contains("Required CI") } == true)
    }

    @Test
    func `only the latest hundred events are retained`() throws {
        let fixture = try AutofixFixture()
        for index in 0 ..< 110 {
            fixture.store.update { $0.pullRequestAutomation[AutofixFixture.key]?.pending = "Wait " + String(index) }
        }
        let log = fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.activityLog
        #expect(log?.count == 100)
        #expect(log?.first?.message == "Wait 10")
        #expect(log?.last?.message == "Wait 109")
    }
}
