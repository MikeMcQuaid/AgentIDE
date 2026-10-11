@testable import AgentIDEData
import AgentIDEDomain
import Testing

struct AutofixResolutionTests {
    @Test
    func `a push claim is exclusive across coordinators`() async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { value in
            value.pullRequestAutomation[AutofixFixture.key]?.isAutomatic = true
            value.pullRequestAutomation[AutofixFixture.key]?.autofixCI = true
            value.pullRequestAutomation[AutofixFixture.key]?.pushAutomatically = true
        }
        let driver = await fixture.driver()
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        let attempt = try #require(await fixture.state.deliveries.first)
        let context = AutofixContext(key: AutofixFixture.key, store: fixture.store, driver: driver)
        #expect(try await AutofixCoordinator().claimPush(attempt, pushKey: AutofixFixture.key, context: context))
        #expect(try await AutofixCoordinator().claimPush(
            attempt, pushKey: AutofixFixture.key, context: context,
        ) == false)
    }

    @Test
    func `an intervening push cancels automatic pushing and cannot resolve newly marked threads`() async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { value in
            value.pullRequestAutomation[AutofixFixture.key]?.isAutomatic = true
            value.pullRequestAutomation[AutofixFixture.key]?.autofixReviews = true
            value.pullRequestAutomation[AutofixFixture.key]?.pushAutomatically = true
        }
        await fixture.update { $0.comments = [AutofixFixture.thread("thread")]; $0.writers = ["human"] }
        let driver = await fixture.driver()
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        await fixture.complete(addressed: ["thread"])
        await fixture.update { $0.freshHead = "external-push" }
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        await fixture.update { $0.head = "external-push" }
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        #expect(await fixture.state.pushes.isEmpty)
        #expect(await fixture.state.resolutions.isEmpty)
    }

    @Test
    func `a stale conversation cache cannot cancel a newer pending mark`() async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { value in
            value.pullRequestAutomation[AutofixFixture.key]?.resolutions["thread"] = .init(
                head: "head", commentID: "new",
            )
        }
        await fixture.update { value in
            value.comments = [AutofixFixture.thread("thread", comment: "old")]
            value.freshComments = [AutofixFixture.thread("thread", comment: "new")]
        }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.resolutions["thread"] != nil)
    }

    @Test
    func `manual marks resolve only after GitHub observes a push without autofix`() async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { value in
            value.pullRequestAutomation[AutofixFixture.key]?.resolutions["thread"] = .init(
                head: "head",
                commentID: "comment",
            )
        }
        await fixture.update { $0.comments = [AutofixFixture.thread("thread")]; $0.hasSession = false }
        let driver = await fixture.driver()
        let coordinator = AutofixCoordinator()
        await coordinator.refresh(store: fixture.store, driver: driver)
        await fixture.update { $0.localHead = "local-commit" }
        await coordinator.refresh(store: fixture.store, driver: driver)
        #expect(await fixture.state.resolutions.isEmpty)
        await fixture.update { $0.head = "external-push"; $0.freshHead = "external-push" }
        await coordinator.refresh(store: fixture.store, driver: driver)
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        #expect(await fixture.state.resolutions == ["thread"])
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.resolutions.isEmpty == true)
    }

    @Test
    func `new comments preserve threads and cancel pending marks`() async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { value in
            value.pullRequestAutomation[AutofixFixture.key]?.resolutions["thread"] = .init(
                head: "head",
                commentID: "comment",
            )
        }
        await fixture.update { value in
            value.comments = [AutofixFixture.thread("thread", comment: "new")]
            value.head = "pushed"; value.freshHead = "pushed"
        }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        #expect(await fixture.state.resolutions.isEmpty)
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.resolutions.isEmpty == true)
    }

    @Test
    func `an ambiguous resolution is claimed once across restarts`() async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { value in
            value.pullRequestAutomation[AutofixFixture.key]?.resolutions["thread"] = .init(
                head: "head",
                commentID: "comment",
            )
        }
        await fixture.update { value in
            value.comments = [AutofixFixture.thread("thread")]
            value.head = "pushed"; value.freshHead = "pushed"; value.failResolution = true
        }
        let driver = await fixture.driver()
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        #expect(await fixture.state.resolutions == ["thread"])
        #expect(fixture.store
            .load()
            .pullRequestAutomation[AutofixFixture.key]?
            .resolutions["thread"]?
            .requested == true)
    }

    @Test(arguments: [false, true])
    func `both fix sources use the shared opt-in push setting`(checks: Bool) async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { $0.pullRequestAutomation[AutofixFixture.key]?.isAutomatic = true }
        fixture.store.update { value in
            value.pullRequestAutomation[AutofixFixture.key]?.autofixCI = checks
            value.pullRequestAutomation[AutofixFixture.key]?.autofixReviews = checks == false
            value.pullRequestAutomation[AutofixFixture.key]?.pushAutomatically = true
        }
        await fixture.update { $0.comments = [AutofixFixture.thread("thread")]; $0.writers = ["human"] }
        let driver = await fixture.driver()
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        await fixture.complete(addressed: checks ? [] : ["thread"])
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        #expect(await fixture.state.pushes == ["fixed"])
        #expect(await fixture.state.resolutions.isEmpty)
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.pushedCommit == "fixed")
        await fixture.update { $0.head = "fixed"; $0.freshHead = "fixed" }
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.pushedCommit == nil)
    }

    @Test
    func `only addressed unchanged threads are marked and a failed push resolves nothing`() async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { $0.pullRequestAutomation[AutofixFixture.key]?.isAutomatic = true }
        fixture.store.update { value in
            value.pullRequestAutomation[AutofixFixture.key]?.autofixReviews = true
            value.pullRequestAutomation[AutofixFixture.key]?.pushAutomatically = true
        }
        await fixture.update { value in
            value.comments = [AutofixFixture.thread("fixed"), AutofixFixture.thread("left", comment: "left")]
            value.writers = ["human"]; value.failPush = true
        }
        let driver = await fixture.driver()
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        await fixture.complete(addressed: ["fixed"])
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.resolutions.keys.sorted() == ["fixed"])
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        #expect(await fixture.state.resolutions.isEmpty)
        #expect(await fixture.state.pushes == ["fixed"])
    }

    @Test
    func `a result without a new commit must not mark threads as addressed`() async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { $0.pullRequestAutomation[AutofixFixture.key]?.isAutomatic = true }
        fixture.store.update { $0.pullRequestAutomation[AutofixFixture.key]?.autofixReviews = true }
        await fixture.update { $0.comments = [AutofixFixture.thread("thread")]; $0.writers = ["human"] }
        let driver = await fixture.driver()
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        await fixture.complete(addressed: ["thread"], commit: "head")
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.resolutions.isEmpty == true)
    }
}
