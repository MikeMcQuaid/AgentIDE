@testable import DashboardFeature
import Foundation
@testable import SanductorData
import Testing

struct SetupTutorialTests {
    @Test(arguments: [false, true])
    func `only new users are offered a tutorial after successful checks`(completed: Bool) async throws {
        let suite = "tutorial-test-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(completed, forKey: SetupModel.completedKey)
        let model = SetupModel(check: { _ in SetupResult(issues: [], agents: [.codexCLI]) }, defaults: defaults)
        #expect(model.tutorialStep == nil)
        #expect(defaults.bool(forKey: "workspaceTutorialPending") == false)
        await model.recheck()
        #expect(defaults.bool(forKey: "workspaceTutorialPending") == (completed == false))
        #expect(model.tutorialStep == (completed ? nil : .repositories))
    }

    @Test(arguments: [false, true])
    func `interrupted and replayed tours wait for checks and stay dismissed`(skip: Bool) async throws {
        let suite = "tutorial-test-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: SetupModel.completedKey)
        defaults.set(true, forKey: "workspaceTutorialPending")
        let model = SetupModel(check: { _ in SetupResult(issues: [], agents: [.codexCLI]) }, defaults: defaults)
        #expect(model.tutorialStep == nil)
        await model.recheck()
        #expect(model.tutorialStep == .repositories)
        if skip {
            model.finishTutorial()
        } else {
            model.advanceTutorial()
            #expect(model.tutorialStep == .agent)
            model.advanceTutorial()
            #expect(model.tutorialStep == .tools)
            model.advanceTutorial()
        }
        #expect(model.tutorialStep == nil)
        #expect(defaults.bool(forKey: "workspaceTutorialPending") == false)
        let reopened = SetupModel(check: { _ in SetupResult(issues: [], agents: [.codexCLI]) }, defaults: defaults)
        await reopened.recheck()
        #expect(reopened.tutorialStep == nil)
    }

    @Test
    func `failed setup never offers or saves a tutorial`() async throws {
        let suite = "tutorial-test-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = SetupModel(check: { _ in
            SetupResult(issues: [
                SetupIssue(step: .sandbox, title: "Repair", explanation: "", commands: "sv build", alternative: ""),
            ], agents: [])
        }, defaults: defaults)
        await model.recheck()
        #expect(model.tutorialStep == nil)
        #expect(defaults.bool(forKey: "workspaceTutorialPending") == false)
    }
}
