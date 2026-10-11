@testable import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

struct AutofixCoordinatorTests {
    @Test
    func `all automatic actions default off`() throws {
        let fixture = try AutofixFixture()
        let state = try #require(fixture.store.load().pullRequestAutomation[AutofixFixture.key])
        #expect(state.isAutomatic == false)
        #expect(state.roundLimit == 1)
        #expect(state.autofixCI == false)
        #expect(state.autofixReviews == false)
        #expect(state.autofixLocalReviews == false)
        #expect(state.pushAutomatically == false)
    }

    @Test
    func `one batch waits for the existing turn and persists before delivery`() async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { $0.pullRequestAutomation[AutofixFixture.key]?.isAutomatic = true }
        let store = fixture.store
        store.update { $0.pullRequestAutomation[AutofixFixture.key]?.autofixCI = true }
        let coordinator = AutofixCoordinator()
        let driver = await fixture.driver()
        await fixture.update { $0.activity = .working }
        await coordinator.refresh(store: store, driver: driver)
        #expect(await fixture.state.deliveries.isEmpty)
        await fixture.update { $0.activity = .done }
        await coordinator.refresh(store: store, driver: driver)
        #expect(await fixture.state.deliveries.count == 1)
        let prompt = try #require(await fixture.state.prompts.first)
        #expect(prompt.contains("test"))
        #expect(prompt.contains("build"))
        #expect(prompt.contains("optional") == false)
        let data = try Data(contentsOf: URL(filePath: fixture.directory + "/state.json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(AppMetadata.self, from: data)
        #expect(restored.pullRequestAutomation[AutofixFixture.key]?.handledEvents == ["run:1"])
        #expect(restored.pullRequestAutomation[AutofixFixture.key]?.attempt != nil)
        store.update { $0.pullRequestAutomation[AutofixFixture.key]?.attempt = nil }
        await AutofixCoordinator().refresh(store: store, driver: driver)
        #expect(await fixture.state.deliveries.count == 1)
    }

    @Test(arguments: [AgentActivity.blocked, .working])
    func `busy agents do not receive prompts`(activity: AgentActivity) async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { $0.pullRequestAutomation[AutofixFixture.key]?.isAutomatic = true }
        fixture.store.update { $0.pullRequestAutomation[AutofixFixture.key]?.autofixCI = true }
        await fixture.update { $0.activity = activity }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        #expect(await fixture.state.deliveries.isEmpty)
    }

    @Test
    func `changed heads and closed sessions never receive fixes`() async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { $0.pullRequestAutomation[AutofixFixture.key]?.isAutomatic = true }
        fixture.store.update { $0.pullRequestAutomation[AutofixFixture.key]?.autofixCI = true }
        await fixture.update { $0.freshHead = "new-head" }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        #expect(await fixture.state.deliveries.isEmpty)
        await fixture.update { $0.freshHead = "head"; $0.hasSession = false }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        #expect(await fixture.state.deliveries.isEmpty)
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.handledEvents.isEmpty == true)
    }

    @Test
    func `review batches include only verified humans and never repeat after a new head`() async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { $0.pullRequestAutomation[AutofixFixture.key]?.isAutomatic = true }
        fixture.store.update { $0.pullRequestAutomation[AutofixFixture.key]?.autofixReviews = true }
        await fixture.update { value in
            value.comments = [
                AutofixFixture.thread("eligible"),
                AutofixFixture.thread("bot", comment: "bot", author: "bot", type: "Bot"),
                AutofixFixture.thread("unknown", comment: "unknown", author: "unknown"),
            ]
            value.writers = ["human", "bot"]
        }
        let driver = await fixture.driver()
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        let prompt = try #require(await fixture.state.prompts.first)
        #expect(prompt.contains("eligible"))
        #expect(prompt.contains("unknown") == false)
        #expect(prompt.contains("bot") == false)
        fixture.store.update { $0.pullRequestAutomation[AutofixFixture.key]?.attempt = nil }
        await fixture.update { $0.head = "new"; $0.freshHead = "new"; $0.localHead = "new" }
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        #expect(await fixture.state.deliveries.count == 1)
    }

    @Test(arguments: [true, false])
    func `permissions and thread state are rechecked before delivery`(revoke: Bool) async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { $0.pullRequestAutomation[AutofixFixture.key]?.isAutomatic = true }
        fixture.store.update { $0.pullRequestAutomation[AutofixFixture.key]?.autofixReviews = true }
        await fixture.update { value in
            value.comments = [AutofixFixture.thread("thread")]
            value.writers = ["human"]
            if revoke {
                value.freshWriters = []
            } else {
                value.freshComments = [AutofixFixture.thread("thread", comment: "new")]
            }
        }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        #expect(await fixture.state.deliveries.isEmpty)
    }
}
