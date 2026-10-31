import Foundation
@testable import SanductorData
import SanductorDomain
import Testing

struct AutofixRecoveryTests {
    @Test
    func `relaunch accepts the outstanding result and keeps watching without repeating fixes`() async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixCI = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixReviews = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
        }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        let file = fixture.directory + "/relaunched.json"
        try FileManager.default.copyItem(atPath: fixture.directory + "/state.json", toPath: file)
        let store = MetadataStore(file: file)
        store.resumeFeedbackLoops()
        let coordinator = AutofixCoordinator()
        await coordinator.refresh(store: store, driver: fixture.driver())
        #expect(await fixture.state.deliveries.count == 1)
        await fixture.complete()
        await coordinator.refresh(store: store, driver: fixture.driver())
        #expect(store.load().pullRequestAutomation[AutofixFixture.key]?.attempt == nil)
        #expect(store.load().pullRequestAutomation[AutofixFixture.key]?.isAutomatic == true)
        await fixture.update { state in
            state.comments = [AutofixFixture.thread("later")]
            state.writers = ["human"]
        }
        await coordinator.refresh(store: store, driver: fixture.driver())
        #expect(await fixture.state.deliveries.count == 2)
        #expect(await fixture.state.deliveries.last?.head == "fixed")
    }

    @Test(arguments: [true, false], [true, false])
    func `launch only retries interrupted collections in active loops`(active: Bool, pending: Bool) throws {
        let fixture = try AutofixFixture()
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixLocalReviews = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
            if active == false {
                metadata.pullRequestAutomation[AutofixFixture.key]?.stopLoop()
            }
            metadata.pullRequestAutomation[AutofixFixture.key]?.localRounds?.started = 1
            metadata.pullRequestAutomation[AutofixFixture.key]?.collection = LocalFeedbackCollection(
                id: "collection", revision: "revision", configuration: "codex", isPending: pending,
            )
        }
        let previous = try #require(fixture.store.load().pullRequestAutomation[AutofixFixture.key])
        fixture.store.resumeFeedbackLoops()
        let current = try #require(fixture.store.load().pullRequestAutomation[AutofixFixture.key])
        #expect(current.isAutomatic == active)
        #expect(current.localRounds == previous.localRounds)
        #expect(current.collection == (active && pending ? nil : previous.collection))
        #expect(current.loopResult == previous.loopResult)
    }

    @Test(arguments: ["review", "ci"])
    func `the last delivery snapshot must still have completed feedback`(change: String) async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixCI = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixBots = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.isAutomatic = true
        }
        var driver = await fixture.driver()
        driver.reviewComments = { _, fresh in
            if fresh {
                await fixture.update { state in
                    if change == "review" {
                        state.requestedReviewers = ["coderabbitai"]
                    } else {
                        state.optionalComplete = false
                    }
                }
            }
            return []
        }
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        #expect(await fixture.state.deliveries.isEmpty)
    }

    @Test(arguments: [true, false])
    func `an empty feedback read cannot finish a newly restarted local stage`(preparing: Bool) async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixReviews = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.isAutomatic = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.preparingExistingWork = preparing
        }
        var driver = await fixture.driver()
        driver.reviewComments = { _, _ in
            fixture.store.update { metadata in
                metadata.pullRequestAutomation[AutofixFixture.key]?.stopLoop()
                metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
            }
            return []
        }
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        let current = try #require(fixture.store.load().pullRequestAutomation[AutofixFixture.key])
        #expect(current.isPreparingExistingWork)
        #expect(current.localRounds?.isComplete == false)
        #expect(current.pending == "Starting feedback loop")
    }

    @Test
    func `newly pending bot feedback cannot fall back to committing dirty work`() async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixBots = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
        }
        await fixture.update { $0.isDirty = true }
        var driver = await fixture.driver()
        driver.prepare = { _, _, candidate in
            await fixture.update { $0.requestedReviewers = ["coderabbitai"] }
            return candidate.text
        }
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        #expect(await fixture.state.deliveries.isEmpty)
    }

    @Test
    func `an observed turn with partially committed work gets one commit follow-up`() async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixCI = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
        }
        let coordinator = AutofixCoordinator()
        let driver = await fixture.driver()
        await coordinator.refresh(store: fixture.store, driver: driver)
        await fixture.update { $0.activity = .working }
        await coordinator.refresh(store: fixture.store, driver: driver)
        await fixture.update { state in
            state.activity = .done
            state.localHead = "partial"
            state.isDirty = true
        }
        await coordinator.refresh(store: fixture.store, driver: driver)
        await coordinator.refresh(store: fixture.store, driver: driver)
        #expect(await fixture.state.deliveries.count == 2)
        #expect(await fixture.state.deliveries.last?.commitRequestedHead == "partial")
    }

    @Test(arguments: [true, false])
    func `completion waits for remote marks and cannot overwrite a restarted loop`(restart: Bool) async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixReviews = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
        }
        await fixture.update { state in
            state.comments = [AutofixFixture.thread("thread")]
            state.writers = ["human"]
        }
        let coordinator = AutofixCoordinator()
        let original = await fixture.driver()
        await coordinator.refresh(store: fixture.store, driver: original)
        await fixture.complete(addressed: ["thread"])
        let driver = AutofixDriver(
            summary: { state, fresh in
                if fresh {
                    if restart {
                        fixture.store.update { metadata in
                            metadata.pullRequestAutomation[AutofixFixture.key]?.stopLoop()
                            metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
                        }
                    } else {
                        return nil
                    }
                }
                return try await original.summary(state, fresh)
            },
            threads: original.threads,
            writers: original.writers,
            target: original.target,
            head: original.head,
            waitReason: original.waitReason,
            deliver: original.deliver,
            result: original.result,
            resolve: original.resolve,
        )
        await coordinator.refresh(store: fixture.store, driver: driver)
        let current = try #require(fixture.store.load().pullRequestAutomation[AutofixFixture.key])
        if restart {
            #expect(current.isPreparingExistingWork)
            #expect(current.lastResult.isEmpty)
            #expect(current.pending == "Starting feedback loop")
        } else {
            #expect(current.attempt != nil)
            await coordinator.refresh(store: fixture.store, driver: original)
            #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.resolutions["thread"] != nil)
            #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.attempt == nil)
        }
    }
}
