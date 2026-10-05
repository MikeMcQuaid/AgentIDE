import AgentIDEData
import AgentIDEDomain
@testable import DashboardFeature
import Foundation
import Testing

@Suite(.serialized)
struct ScheduledPromptsModelTests {
    // MARK: Internal

    @Test
    func `overdue schedules catch up once and claim before launch`() async {
        let fixture = SessionNavigationTests.Fixture()
        defer { fixture.close() }
        let prompt = prompt()
        fixture.model.store.update { metadata in
            metadata.scheduledPrompts = [prompt]
            metadata.prompts["existing"] = "keep"
        }
        let model = makeModel(fixture)
        var launches = 0
        model.launch = { launched, due in
            launches += 1
            #expect(launched.prompt == prompt.prompt)
            #expect(due == prompt.nextRun)
            let claimed = try #require(fixture.model.store.load().scheduledPrompts.first)
            #expect(try #require(claimed.nextRun) > model.now())
            await model.runDue()
            return "scheduled-session"
        }
        await model.runDue()
        await model.runDue()
        #expect(launches == 1)
        #expect(model.prompts.first?.lastSession == "scheduled-session")
        #expect(model.prompts.first?.lastError == nil)
        #expect(fixture.model.store.load().prompts["existing"] == "keep")
        let reloaded = makeModel(fixture)
        reloaded.launch = { _, _ in
            Issue.record("A restart must not repeat the run")
            return "unexpected"
        }
        await reloaded.runDue()
    }

    @Test
    func `paused schedules do not catch up when enabled again`() async throws {
        let fixture = SessionNavigationTests.Fixture()
        defer { fixture.close() }
        var prompt = prompt()
        prompt.isEnabled = false
        fixture.model.store.update { $0.scheduledPrompts = [prompt] }
        let model = makeModel(fixture)
        model.launch = { _, _ in
            Issue.record("Paused schedules must not launch")
            return "unexpected"
        }
        await model.runDue()
        prompt.isEnabled = true
        #expect(model.save(prompt))
        #expect(try #require(model.prompts.first?.nextRun) > model.now())
        await model.runDue()
        model.delete(prompt)
        #expect(model.prompts.isEmpty)
        #expect(fixture.model.store.load().scheduledPrompts.isEmpty)
    }

    @Test
    func `a retry uses the same occurrence and saving an open editor preserves its result`() async throws {
        let fixture = SessionNavigationTests.Fixture()
        defer { fixture.close() }
        var draft = prompt()
        fixture.model.store.update { $0.scheduledPrompts = [draft] }
        let model = makeModel(fixture)
        var branches = [String]()
        model.launch = { prompt, due in
            branches.append(prompt.branch(for: due))
            if branches.count == 1 {
                throw CocoaError(.fileReadUnknown)
            }
            return "recovered"
        }
        await model.runDue()
        #expect(branches.count == 2)
        #expect(branches.first == branches.last)
        draft.prompt = "Updated while launching"
        #expect(model.save(draft))
        #expect(model.prompts.first?.lastSession == "recovered")
        #expect(model.prompts.first?.lastError == nil)
        #expect(try #require(model.prompts.first?.nextRun) > model.now())
    }

    @Test
    func `a schedule disabled while another launches is left alone`() async {
        let fixture = SessionNavigationTests.Fixture()
        defer { fixture.close() }
        let first = prompt()
        var second = prompt()
        fixture.model.store.update { $0.scheduledPrompts = [first, second] }
        let model = makeModel(fixture)
        var launches = 0
        model.launch = { _, _ in
            launches += 1
            second.isEnabled = false
            #expect(model.save(second))
            return "first"
        }
        await model.runDue()
        #expect(launches == 1)
    }

    @Test
    func `a failed durable claim never launches and can be retried after repair`() async throws {
        let fixture = SessionNavigationTests.Fixture()
        defer { fixture.close() }
        let prompt = prompt()
        fixture.model.store.update { $0.scheduledPrompts = [prompt] }
        let model = makeModel(fixture)
        let file = fixture.root + "/state.json"
        try FileManager.default.removeItem(atPath: file)
        try FileManager.default.createDirectory(atPath: file, withIntermediateDirectories: true)
        var launches = 0
        model.launch = { _, _ in
            launches += 1
            return "after-repair"
        }
        await model.runDue()
        #expect(launches == 0)
        #expect(model.error != nil)
        try FileManager.default.removeItem(atPath: file)
        await model.runDue()
        #expect(launches == 1)
        #expect(model.error == nil)
    }

    // MARK: Private

    private func prompt() -> ScheduledPrompt {
        var prompt = ScheduledPrompt(repositoryPath: "/repository")
        prompt.name = "Daily review"
        prompt.prompt = "Check recent changes"
        prompt.nextRun = Date(timeIntervalSince1970: 1_893_488_400)
        prompt.schedule.timeZoneIdentifier = "UTC"
        return prompt
    }

    private func makeModel(_ fixture: SessionNavigationTests.Fixture) -> ScheduledPromptsModel {
        let model = ScheduledPromptsModel(store: fixture.model.store, service: fixture.model.service)
        model.now = { Date(timeIntervalSince1970: 1_893_686_400) }
        return model
    }
}
