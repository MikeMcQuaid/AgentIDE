@testable import DashboardFeature
import Foundation
import SanductorDomain
import Testing

extension ScheduledPromptsModelTests {
    @Test(arguments: [false, true], [false, true])
    func `start uses the saved job and preserves future dates and pauses`(enabled: Bool, overdue: Bool) async throws {
        let fixture = SessionNavigationTests.Fixture()
        defer { fixture.close() }
        var saved = prompt()
        let model = makeModel(fixture)
        saved.agent = .codexCLI
        saved.model = "saved model"
        saved.effort = "high"
        saved.isEnabled = enabled
        #expect(model.save(saved))
        saved.nextRun = model.now().addingTimeInterval(overdue ? -3_600 : 3_600)
        fixture.model.store.update { $0.scheduledPrompts = [saved] }
        let loaded = makeModel(fixture)
        var launches = 0
        loaded.launch = { launched, due in
            launches += 1
            #expect(launched == saved)
            #expect(due == loaded.now())
            #expect(fixture.model.store.load().scheduledPrompts.first?.lastRun == due)
            await loaded.start(saved)
            await loaded.runDue()
            return "manual-session"
        }
        var stale = saved
        stale.prompt = "Unsaved changes"
        await loaded.start(stale)
        await loaded.runDue()
        #expect(launches == 1)
        let result = try #require(loaded.prompts.first)
        #expect(result.isEnabled == enabled)
        #expect(result.nextRun == (enabled && overdue ? saved.schedule.nextRun(after: loaded.now()) : saved.nextRun))
        #expect(result.lastSession == "manual-session")
        #expect(result.lastError == nil)
        #expect(loaded.runningID == nil)
        loaded.delete(saved)
        await loaded.start(saved)
        #expect(launches == 1)
    }

    @Test
    func `manual retries reuse one branch and later starts get a new one`() async throws {
        let fixture = SessionNavigationTests.Fixture()
        defer { fixture.close() }
        let saved = prompt()
        let model = makeModel(fixture)
        #expect(model.save(saved))
        let next = try #require(model.prompts.first?.nextRun)
        var branches = [String]()
        model.launch = { prompt, due in
            branches.append(prompt.branch(for: due))
            if branches.count == 1 {
                throw CocoaError(.fileReadUnknown)
            }
            return "manual-session"
        }
        await model.start(saved)
        #expect(branches.count == 2)
        #expect(branches.first == branches.last)
        await model.start(saved)
        #expect(branches.count == 3)
        #expect(branches.first != branches.last)
        #expect(model.prompts.first?.nextRun == next)
        #expect(model.prompts.first?.lastError == nil)
    }
}
