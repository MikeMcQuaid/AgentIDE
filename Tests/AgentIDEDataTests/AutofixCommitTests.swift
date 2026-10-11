@testable import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

struct AutofixCommitTests {
    @Test
    func `restarting handled CI with uncommitted fixes recovers only the commit step`() async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixCI = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.pushAutomatically = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.handledEvents = ["run:1"]
            metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
        }
        await fixture.update { $0.isDirty = true }
        let driver = await fixture.driver()
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        let recovery = try #require(await fixture.state.deliveries.first)
        #expect(recovery.commitRequestedHead == "head")
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.activityStatus
            == "Commit-only prompt sent; waiting for the agent to commit existing fixes")
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.roundsStarted == 0)
        #expect(await fixture.state.pushes.isEmpty)
        await fixture.complete()
        await fixture.update { $0.isDirty = false }
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        #expect(await fixture.state.pushes == ["fixed"])
        #expect(await fixture.state.deliveries.count == 1)
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.pushedCommit = nil
            metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
        }
        await fixture.update { $0.isDirty = true; $0.localHead = "head" }
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        #expect(await fixture.state.deliveries.count == 1)
    }

    @Test(arguments: [true, false], [true, false])
    func `uncommitted fixes get one commit follow-up before the app pushes`(
        reportsResult: Bool, automaticPush: Bool,
    ) async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixCI = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.pushAutomatically = automaticPush
            metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
        }
        let driver = await fixture.driver()
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        let original = try #require(await fixture.state.deliveries.first)
        if reportsResult {
            await fixture.complete(commit: "head")
        } else {
            await fixture.update { $0.activity = .working }
            await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
            await fixture.update { $0.activity = .done }
        }
        await fixture.update { $0.isDirty = true }
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        #expect(await fixture.state.deliveries.count == 2)
        #expect(await fixture.state.deliveries.last?.id == original.id)
        #expect(await fixture.state.pushes.isEmpty)
        #expect(await fixture.state.deliveries.last?.commitRequestedHead == "head")
        let stored = fixture.store.load()
        #expect(stored.pullRequestAutomation[AutofixFixture.key]?.roundsStarted == 1)
        let restored = try JSONDecoder().decode(AppMetadata.self, from: JSONEncoder().encode(stored))
        fixture.store.update { $0 = restored }
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        #expect(await fixture.state.deliveries.count == 2)
        await fixture.update { $0.localHead = "fixed"; $0.isDirty = false }
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        #expect(await fixture.state.pushes.isEmpty)
        await fixture.complete()
        await fixture.update { $0.isDirty = false; $0.activity = .working }
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        #expect(await fixture.state.pushes.isEmpty)
        await fixture.update { $0.activity = .done }
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        #expect(await fixture.state.pushes == (automaticPush ? ["fixed"] : []))
        #expect(await fixture.state.deliveries.count == 2)
    }

    @Test(arguments: ["working", "blocked", "missing", "head", "remote", "disabled"])
    func `commit follow-ups respect readiness and captured heads`(changed: String) async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixCI = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
        }
        let driver = await fixture.driver()
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        await fixture.complete(commit: "head")
        await fixture.update { state in
            state.isDirty = true
            switch changed {
            case "working":
                state.activity = .working

            case "blocked":
                state.activity = .blocked

            case "missing":
                state.hasSession = false

            case "head":
                state.localHead = "changed"

            case "remote":
                state.freshHead = "changed"

            default:
                break
            }
        }
        if changed == "disabled" {
            fixture.store.update { $0.pullRequestAutomation[AutofixFixture.key]?.isAutomatic = false }
        }
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        #expect(await fixture.state.deliveries.count == 1)
        #expect(await fixture.state.pushes.isEmpty)
    }

    @Test
    func `an ambiguous commit request is claimed before delivery and never repeated`() async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixCI = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
        }
        let driver = await fixture.driver()
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        await fixture.complete(commit: "head")
        await fixture.update { $0.isDirty = true }
        let attempt = try #require(await fixture.state.deliveries.first)
        var refusing = driver
        refusing.deliver = { attempt, text in
            let claimed = fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.attempt
            #expect(claimed?.commitRequestedHead == "head")
            try await driver.deliver(attempt, text)
            throw SessionServiceError("Delivery unconfirmed")
        }
        await AutofixCoordinator().refresh(store: fixture.store, driver: refusing)
        await AutofixCoordinator().refresh(store: fixture.store, driver: refusing)
        #expect(await fixture.state.deliveries.count == 2)
        #expect(await fixture.state.deliveries.last?.id == attempt.id)
        let state = try #require(fixture.store.load().pullRequestAutomation[AutofixFixture.key])
        #expect(state.lastResult.contains("unconfirmed"))
    }

    @Test
    func `already attempted red CI is not labelled finished`() async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixCI = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.handledEvents = ["run:1"]
            metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
        }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        let state = try #require(fixture.store.load().pullRequestAutomation[AutofixFixture.key])
        #expect(state.loopStatus == "Failed")
        #expect(state.lastResult.contains("already attempted"))
        #expect(await fixture.state.deliveries.isEmpty)
    }

    @Test
    func `idle state before the fixing turn starts cannot trigger a commit request`() async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixCI = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
        }
        let driver = await fixture.driver()
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        await fixture.update { $0.isDirty = true }
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        #expect(await fixture.state.deliveries.count == 1)
    }
}
