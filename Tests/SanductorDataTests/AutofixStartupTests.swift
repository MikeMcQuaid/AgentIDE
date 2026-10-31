@testable import SanductorData
import SanductorDomain
import Testing

struct AutofixStartupTests {
    @Test
    func `unresolved previously attempted local findings need attention before new rounds`() async throws {
        let fixture = try AutofixFixture()
        let review = LocalReview(
            reviewer: .codexCLI, snapshot: "diff", revision: "revision", threads: [AutofixFixture.thread("local")],
        )
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixLocalReviews = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.handledEvents = ["local:" + (review.runID ?? "")]
            metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
        }
        await fixture.update { $0.localReview = review }
        var driver = await fixture.driver()
        driver.localReview = { state in state.feedbackWorktreePath == "/worktree" ? review : nil }
        driver.collect = { _, _, _ in Issue.record("Existing findings still need attention"); return nil }
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        #expect(await fixture.state.deliveries.isEmpty)
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.loopResult == .failed)
    }

    @Test(arguments: ["ci", "head", "revision", "working", "permissions"])
    func `startup still gates incomplete or changed feedback`(change: String) async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixCI = change == "ci"
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixReviews = change == "permissions"
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixBots = change != "permissions"
            metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
        }
        await fixture.update { state in
            state.comments = [
                AutofixFixture.thread(
                    "comment",
                    author: change == "permissions" ? "human" : "coderabbitai[bot]",
                    type: change == "permissions" ? "User" : "Bot",
                ),
            ]
            if change == "ci" {
                state.checksComplete = false
            }
            if change == "head" {
                state.freshHead = "changed"
            }
            if change == "working" {
                state.activity = .working
            }
            if change == "revision" {
                state.comments = []; state.isDirty = true
            }
        }
        var driver = await fixture.driver()
        if change == "revision" {
            driver.prepare = { _, _, candidate in
                await fixture.update { $0.isDirty = false }
                return candidate.text
            }
        }
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        #expect(await fixture.state.deliveries.isEmpty)
    }

    @Test
    func `restarting unfinished local work never delivers the same preparation twice`() async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixLocalReviews = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
        }
        await fixture.update { $0.isDirty = true }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        fixture.store.update { $0.pullRequestAutomation[AutofixFixture.key]?.stopLoop() }
        fixture.store.update { $0.pullRequestAutomation[AutofixFixture.key]?.startLoop() }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        #expect(await fixture.state.deliveries.count == 1)
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.loopResult == .failed)
    }

    @Test
    func `existing remote feedback is fixed before requesting a local or bot review`() async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixLocalReviews = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixCI = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixBots = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
        }
        await fixture.update { state in
            state.comments = [AutofixFixture.thread("bot", author: "coderabbitai[bot]", type: "Bot")]
        }
        var driver = await fixture.driver()
        driver.collect = { _, _, _ in Issue.record("Existing feedback must precede a new review"); return nil }
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        #expect(await fixture.state.deliveries.first?.sources == [.checks, .codeRabbit])
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.localRoundsStarted == 0)
        let activity = fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.activityLog ?? []
        #expect(activity.contains { $0.message.contains("local round 0") } == false)
        await fixture.complete(commit: "fixed")
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.isLocalStage == true)
    }

    @Test
    func `existing local findings do not launch a replacement review`() async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixLocalReviews = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
        }
        await fixture.update { state in
            state.localReview = LocalReview(
                reviewer: .codexCLI, snapshot: "diff", revision: "revision", threads: [AutofixFixture.thread("local")],
            )
        }
        var driver = await fixture.driver()
        driver.collect = { _, _, _ in Issue.record("Use the current local findings first"); return nil }
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        #expect(await fixture.state.deliveries.first?.sources == [.localReview])
    }

    @Test(arguments: [true, false])
    func `uncommitted starting work is finished before fresh review requests`(localOnly: Bool) async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.localWorktreePath = localOnly ? "/worktree" : nil
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixLocalReviews = localOnly
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixBots = localOnly == false
            metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
        }
        await fixture.update { $0.isDirty = true }
        var driver = await fixture.driver()
        driver.reviewComments = { _, _ in
            #expect(localOnly == false)
            return []
        }
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        #expect(await fixture.state.deliveries.count == 1)
        #expect(await fixture.state.prompts.first?.contains("uncommitted") == true)
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.localRoundsStarted == 0)
        await fixture.complete(commit: "fixed")
        await fixture.update { $0.isDirty = false }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.isPreparingExistingWork == false)
    }

    @Test
    func `unpushed local commits can receive published feedback`() async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixCI = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
        }
        await fixture.update { $0.localHead = "unpushed" }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        #expect(await fixture.state.deliveries.count == 1)
        #expect(await fixture.state.prompts.first?.contains("Fix these failed CI") == true)
        await fixture.complete(commit: "unpushed")
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
    }
}
