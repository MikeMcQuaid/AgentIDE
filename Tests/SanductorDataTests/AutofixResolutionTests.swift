@testable import SanductorData
import SanductorDomain
import Testing

struct AutofixResolutionTests {
    @Test
    func `an intervening push cannot resolve newly marked threads`() async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { value in
            value.pullRequestAutomation[AutofixFixture.key]?.isAutomatic = true
            value.pullRequestAutomation[AutofixFixture.key]?.autofixReviews = true
        }
        await fixture.update { $0.comments = [AutofixFixture.thread("thread")]; $0.writers = ["human"] }
        let driver = await fixture.driver()
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        await fixture.complete(addressed: ["thread"])
        await fixture.update { $0.freshHead = "external-push" }
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        await fixture.update { $0.head = "external-push" }
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        #expect(await fixture.state.resolutions.isEmpty)
    }

    @Test
    func `later unrelated pushes cannot resolve locally fixed threads`() async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixReviews = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
        }
        await fixture.update { state in
            state.comments = [AutofixFixture.thread("thread")]
            state.writers = ["human"]
        }
        let driver = await fixture.driver()
        let coordinator = AutofixCoordinator()
        await coordinator.refresh(store: fixture.store, driver: driver)
        await fixture.complete(addressed: ["thread"])
        await coordinator.refresh(store: fixture.store, driver: driver)
        await fixture.update { $0.head = "unrelated"; $0.freshHead = "unrelated" }
        await coordinator.refresh(store: fixture.store, driver: driver)
        #expect(await fixture.state.resolutions.isEmpty)
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.resolutions["thread"] != nil)
        await fixture.update { $0.head = "fixed"; $0.freshHead = "fixed" }
        await coordinator.refresh(store: fixture.store, driver: driver)
        #expect(await fixture.state.resolutions == ["thread"])
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
    func `both fix sources stay local until the user pushes`(checks: Bool) async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { $0.pullRequestAutomation[AutofixFixture.key]?.isAutomatic = true }
        fixture.store.update { value in
            value.pullRequestAutomation[AutofixFixture.key]?.autofixCI = checks
            value.pullRequestAutomation[AutofixFixture.key]?.autofixReviews = checks == false
        }
        await fixture.update { $0.comments = [AutofixFixture.thread("thread")]; $0.writers = ["human"] }
        let driver = await fixture.driver()
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        await fixture.complete(addressed: checks ? [] : ["thread"])
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        #expect(await fixture.state.resolutions.isEmpty)
        await fixture.update { $0.head = "fixed"; $0.freshHead = "fixed" }
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
    }

    @Test
    func `only addressed unchanged threads are marked and local commits resolve nothing`() async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { $0.pullRequestAutomation[AutofixFixture.key]?.isAutomatic = true }
        fixture.store.update { value in
            value.pullRequestAutomation[AutofixFixture.key]?.autofixReviews = true
        }
        await fixture.update { value in
            value.comments = [AutofixFixture.thread("fixed"), AutofixFixture.thread("left", comment: "left")]
            value.writers = ["human"]
        }
        let driver = await fixture.driver()
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        await fixture.complete(addressed: ["fixed"])
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.resolutions.keys.sorted() == ["fixed"])
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        #expect(await fixture.state.resolutions.isEmpty)
    }

    @Test
    func `verified existing fixes on the current commit are marked resolve on push`() async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { $0.pullRequestAutomation[AutofixFixture.key]?.isAutomatic = true }
        fixture.store.update { $0.pullRequestAutomation[AutofixFixture.key]?.autofixReviews = true }
        await fixture.update { $0.comments = [AutofixFixture.thread("thread")]; $0.writers = ["human"] }
        let driver = await fixture.driver()
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        await fixture.complete(addressed: ["thread"], commit: "head")
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        #expect(fixture.store
            .load()
            .pullRequestAutomation[AutofixFixture.key]?
            .resolutions["thread"]?
            .fixCommit == "head")
        #expect(await fixture.state.resolutions.isEmpty)
    }
}
