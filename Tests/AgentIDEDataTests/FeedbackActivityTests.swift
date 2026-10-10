@testable import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

struct FeedbackActivityTests {
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
        #expect(log?.last?.message == "Waiting for 1 required CI job")
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
