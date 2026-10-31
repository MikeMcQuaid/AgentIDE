@testable import SanductorData
import SanductorDomain
import Testing

struct AutofixConflictTests {
    @Test(arguments: ["target", "base", "head", "dirty", "stopped"])
    func `a rebase is revalidated after prompt preparation`(change: String) async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixReviews = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
        }
        await fixture.update { $0.mergeable = "CONFLICTING" }
        var driver = await fixture.driver()
        driver.prepare = { _, _, candidate in
            await fixture.update { state in
                switch change {
                case "target":
                    state.baseBranch = "new-target"

                case "base":
                    state.conflictBase = "new-base"

                case "head":
                    state.localHead = "new-head"

                case "dirty":
                    state.isDirty = true

                default:
                    break
                }
            }
            if change == "stopped" {
                fixture.store.update { $0.pullRequestAutomation[AutofixFixture.key]?.stopLoop() }
            }
            return candidate.text
        }
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        #expect(await fixture.state.deliveries.isEmpty)
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.handledEvents.isEmpty == true)
    }

    @Test(arguments: ["working", "blocked", "dirty", "missing", "diverged", "resolved"])
    func `conflicts need a clean idle worktree and an unintegrated target`(blocked: String) async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixReviews = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
        }
        await fixture.update { state in
            state.mergeable = "CONFLICTING"
            switch blocked {
            case "working":
                state.activity = .working

            case "blocked":
                state.activity = .blocked

            case "dirty":
                state.isDirty = true

            case "missing":
                state.hasSession = false

            case "diverged":
                state.localHead = "other"; state.containsRemoteHead = false

            default:
                state.conflictBase = nil
            }
        }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        #expect(await fixture.state.deliveries.isEmpty)
    }

    @Test
    func `a verified rebase preserves resolution marks and watching on the published head`() async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixReviews = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
            metadata.pullRequestAutomation[AutofixFixture.key]?.localRounds?.started = 1
            metadata.pullRequestAutomation[AutofixFixture.key]?.resolutions["fixed"] = PendingThreadResolution(
                head: "head", commentID: "fixed", fixCommit: "head",
            )
        }
        await fixture.update { state in
            state.mergeable = "CONFLICTING"
            state.comments = [AutofixFixture.thread("fixed", comment: "fixed")]
        }
        let coordinator = AutofixCoordinator()
        let driver = await fixture.driver()
        await coordinator.refresh(store: fixture.store, driver: driver)
        #expect(await fixture.state.deliveries.count == 1)
        await fixture.complete(commit: "rebased")
        await fixture.update { state in
            state.conflictBase = nil
            state.containsRemoteHead = false
            state.containedHeads = ["base", "rebased"]
        }
        await coordinator.refresh(store: fixture.store, driver: driver)
        let saved = try #require(fixture.store.load().pullRequestAutomation[AutofixFixture.key])
        #expect(saved.attempt == nil)
        #expect(saved.rebasedHeads == ["head": "rebased"])
        #expect(saved.localRoundsStarted == 1)
        #expect(saved.resolutions["fixed"]?.fixCommit == "rebased")
        #expect(await fixture.state.resolutions.isEmpty)
        fixture.store.resumeFeedbackLoops()
        await fixture.update { state in
            state.writers = ["human"]
            state.comments.append(AutofixFixture.thread("later", comment: "later"))
        }
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        #expect(await fixture.state.deliveries.count == 2)
        #expect(await fixture.state.deliveries.last?.head == "rebased")
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.stopLoop()
            metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
        }
        await fixture.update { $0.head = "new-published-head"; $0.freshHead = "new-published-head" }
        await coordinator.refresh(store: fixture.store, driver: driver)
        #expect(await fixture.state.deliveries.count == 2)
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.pending.contains("Integrate") == true)
    }

    @Test
    func `rebase completion requires the captured target in the resulting history`() async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixReviews = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
        }
        await fixture.update { $0.mergeable = "CONFLICTING" }
        let coordinator = AutofixCoordinator()
        let driver = await fixture.driver()
        await coordinator.refresh(store: fixture.store, driver: driver)
        await fixture.complete(commit: "unrebased")
        await fixture.update { $0.containsRemoteHead = false }
        await coordinator.refresh(store: fixture.store, driver: driver)
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.attempt != nil)
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.rebasedHeads.isEmpty == true)
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.stopLoop()
            metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
        }
        await fixture.update { $0.localHead = "head"; $0.containsRemoteHead = true }
        await coordinator.refresh(store: fixture.store, driver: driver)
        #expect(await fixture.state.deliveries.count == 1)
    }

    @Test
    func `upstream conflicts trigger a local rebase before blocked CI and reviews`() async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixCI = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixBots = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
        }
        await fixture.update { state in
            state.mergeable = "CONFLICTING"
            state.baseBranch = "release/next"
            state.checksComplete = false
            state.requestedReviewers = ["coderabbitai"]
        }
        let driver = await fixture.driver()
        let coordinator = AutofixCoordinator()
        await coordinator.refresh(store: fixture.store, driver: driver)
        let prompt = try #require(await fixture.state.prompts.first)
        #expect(prompt.contains("rebase"))
        #expect(prompt.contains("origin/release/next"))
        #expect(prompt.contains("feature"))
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.localRoundsStarted == 0)
        await coordinator.refresh(store: fixture.store, driver: driver)
        #expect(await fixture.state.deliveries.count == 1)
    }
}
