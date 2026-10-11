@testable import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

struct CodeRabbitLoopTests {
    // MARK: Internal

    @Test
    func `review requests survive restarts and wait for evidence on the current head`() async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { value in
            value.pullRequestAutomation[AutofixFixture.key]?.autofixCodeRabbit = true
            value.pullRequestAutomation[AutofixFixture.key]?.isAutomatic = true
        }
        for _ in 0 ..< 2 {
            await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        }
        #expect(await fixture.state.requestedBots == [.codeRabbit])
        #expect(await fixture.state.deliveries.isEmpty)
        let restarted = MetadataStore(file: fixture.directory + "/state.json")
        await AutofixCoordinator().refresh(store: restarted, driver: fixture.driver())
        #expect(await fixture.state.requestedBots == [.codeRabbit])
        await fixture.update { $0.reviewEvents = [review(head: "stale")] }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        #expect(await fixture.state.deliveries.isEmpty)
        await fixture.update { $0.reviewEvents = [review(head: "head")] }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        #expect(await fixture.state.deliveries.count == 1)
        #expect(await fixture.state.requestedBots == [.codeRabbit])
    }

    @Test
    func `CI and CodeRabbit share one attempt and only addressed threads resolve`() async throws {
        let fixture = try await readyFixture()
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        let attempt = try #require(await fixture.state.deliveries.first)
        #expect(attempt.sources == [.checks, .codeRabbit])
        #expect(attempt.threads.keys.sorted() == ["thread"])
        #expect(await fixture.state.prompts.first?.contains("Assert the matrix output") == true)
        await fixture.complete(addressed: ["thread"])
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        #expect(await fixture.state.resolutions.isEmpty)
        await fixture.update { $0.head = "fixed"; $0.freshHead = "fixed" }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        #expect(await fixture.state.resolutions == ["thread"])
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        #expect(await fixture.state.deliveries.count == 1)
        #expect(await fixture.state.resolutions == ["thread"])
    }

    @Test(arguments: [true, false])
    func `changed heads or summary findings block delivery`(changesHead: Bool) async throws {
        let fixture = try await readyFixture()
        await fixture.update { value in
            if changesHead {
                value.freshHead = "changed"
            } else {
                value.freshReviewEvents = []
            }
        }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        #expect(await fixture.state.deliveries.isEmpty)
    }

    @Test
    func `legacy dual selections request only one reviewer without filling the activity log`() async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { value in
            value.pullRequestAutomation[AutofixFixture.key]?.autofixCopilot = true
            value.pullRequestAutomation[AutofixFixture.key]?.autofixCodeRabbit = true
            value.pullRequestAutomation[AutofixFixture.key]?.isAutomatic = true
        }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        let log = fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.activityLog
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.activityLog == log)
        #expect(await fixture.state.requestedBots == [.codeRabbit])
    }

    @Test
    func `changing the chosen reviewer cannot request both even after a restart`() async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { value in
            value.pullRequestAutomation[AutofixFixture.key]?.autofixBots = true
            value.pullRequestAutomation[AutofixFixture.key]?.reviewBot = .codeRabbit
            value.pullRequestAutomation[AutofixFixture.key]?.isAutomatic = true
        }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        fixture.store.update { $0.pullRequestAutomation[AutofixFixture.key]?.reviewBot = .copilot }
        let file = fixture.directory + "/restarted.json"
        try FileManager.default.copyItem(atPath: fixture.directory + "/state.json", toPath: file)
        let restarted = MetadataStore(file: file)
        await AutofixCoordinator().refresh(store: restarted, driver: fixture.driver())
        #expect(await fixture.state.requestedBots == [.codeRabbit])
        await fixture.update { value in
            value.reviewEvents = [review(head: "head")]
            value.comments = [AutofixFixture.thread("copilot", author: "copilot-pull-request-reviewer", type: "Bot")]
        }
        await AutofixCoordinator().refresh(store: restarted, driver: fixture.driver())
        #expect(await fixture.state.requestedBots == [.codeRabbit])
        #expect(await fixture.state.deliveries.first?.sources == [.codeRabbit, .copilot])
        #expect(restarted.load().pullRequestAutomation[AutofixFixture.key]?.reviewBot == .copilot)
    }

    // MARK: Private

    private func readyFixture() async throws -> AutofixFixture {
        let fixture = try AutofixFixture()
        fixture.store.update { value in
            value.pullRequestAutomation[AutofixFixture.key]?.autofixCI = true
            value.pullRequestAutomation[AutofixFixture.key]?.autofixCodeRabbit = true
            value.pullRequestAutomation[AutofixFixture.key]?.isAutomatic = true
        }
        await fixture.update { value in
            value.reviewEvents = [review(head: "head")]
            value.comments = [AutofixFixture.thread("thread", author: "coderabbitai[bot]", type: "Bot")]
        }
        return fixture
    }

    private func review(head: String) -> ReviewComment {
        ReviewComment(
            id: 1,
            author: "coderabbitai[bot]",
            body: CodeRabbitTests.finding,
            kind: "COMMENTED",
            nodeID: "summary",
            authorType: "Bot",
            commit: head,
            date: Date().addingTimeInterval(1),
        )
    }
}
