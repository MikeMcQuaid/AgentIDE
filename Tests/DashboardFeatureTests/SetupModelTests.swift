@testable import DashboardFeature
import Foundation
@testable import SanductorData
import Synchronization
import Testing

struct SetupModelTests {
    @Test
    func `online success is saved only after every prerequisite passes`() async throws {
        let suite = "setup-test-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let attempts = Mutex<[Bool]>([])
        let model = SetupModel(check: { online in
            let first = attempts.withLock { attempts in
                attempts.append(online)
                return attempts.count == 1
            }
            return SetupResult(issues: first ? [
                SetupIssue(
                    step: .tools, title: "Missing", explanation: "Install", commands: "install", alternative: "",
                ),
            ] : [], agents: [.codexCLI])
        }, defaults: defaults)
        await model.recheck()
        #expect(model.isReady == false)
        #expect(defaults.bool(forKey: SetupModel.completedKey) == false)
        await model.recheck()
        #expect(model.isReady)
        #expect(defaults.string(forKey: "agentKind") == "codex")
        #expect(attempts.withLock { $0 } == [true, true])
        let reopened = SetupModel(check: { online in
            attempts.withLock { $0.append(online) }
            return SetupResult(issues: [], agents: [.codexCLI])
        }, defaults: defaults)
        #expect(reopened.isReady)
        await reopened.checkOnLaunch()
        await reopened.checkOnLaunch()
        #expect(reopened.isReady)
        #expect(attempts.withLock { $0 } == [true, true, false])
    }

    @Test(arguments: [false, true], [false, true])
    func `setup preserves explicit signing choices`(configured: Bool, required: Bool) async throws {
        let suite = "setup-test-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(required, forKey: AppSettings.requireSignedCommitsKey)
        let model = SetupModel(check: { _ in
            SetupResult(issues: [], agents: [.codexCLI], signingConfigured: configured)
        }, defaults: defaults)
        await model.recheck()
        #expect(model.isReady)
        #expect(defaults.bool(forKey: AppSettings.requireSignedCommitsKey) == required)
        #expect(model.signingDisabled == false)
    }

    @Test(arguments: [false, true], [false, true])
    func `only first-time setup defaults unavailable signing off`(configured: Bool, completed: Bool) async throws {
        let suite = "setup-test-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(completed, forKey: SetupModel.completedKey)
        let model = SetupModel(check: { _ in
            SetupResult(issues: [], agents: [.codexCLI], signingConfigured: configured)
        }, defaults: defaults)
        await model.recheck()
        #expect(model.isReady)
        #expect(defaults.object(forKey: AppSettings.requireSignedCommitsKey) as? Bool
            == (configured || completed ? nil : false))
        #expect(model.signingDisabled == (configured == false && completed == false))
    }

    @Test
    func `the wizard stays on an unfinished step and advances after repair`() async throws {
        let suite = "setup-test-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let attempts = Mutex(0)
        let model = SetupModel(check: { _ in
            let attempt = attempts.withLock { $0 += 1; return $0 }
            let issues = [
                SetupIssue(step: .github, title: "GitHub", explanation: "", commands: "login", alternative: ""),
                SetupIssue(step: .agent, title: "Agent", explanation: "", commands: "login", alternative: ""),
            ]
            return SetupResult(issues: attempt < 3 ? issues : Array(issues.dropFirst()), agents: [])
        }, defaults: defaults)
        await model.recheck()
        #expect(model.currentIssue?.step == .github)
        await model.recheck()
        #expect(model.currentIssue?.step == .github)
        await model.recheck()
        #expect(model.currentIssue?.step == .agent)
        #expect(model.isReady == false)
    }

    @Test(arguments: [false, true])
    func `slow checks keep completed setups ready and reject duplicate rechecks`(completed: Bool) async throws {
        let suite = "setup-test-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(completed, forKey: SetupModel.completedKey)
        let waiting = Mutex<CheckedContinuation<SetupResult, Never>?>(nil)
        let model = SetupModel(check: { _ in
            await withCheckedContinuation { continuation in waiting.withLock { $0 = continuation } }
        }, defaults: defaults)
        let task = Task {
            await model.recheck()
        }
        while waiting.withLock({ $0 == nil }) {
            await Task.yield()
        }
        #expect(model.isChecking)
        #expect(model.isReady == completed)
        await model.recheck()
        waiting.withLock { $0 }?.resume(returning: SetupResult(issues: [], agents: [.codexCLI]))
        await task.value
        #expect(model.isReady)
        #expect(model.isChecking == false)
    }

    @Test
    func `a background failure gates the workspace until a manual recheck succeeds`() async throws {
        let suite = "setup-test-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: SetupModel.completedKey)
        let attempts = Mutex(0)
        let model = SetupModel(check: { online in
            #expect(online == false)
            let first = attempts.withLock { $0 += 1; return $0 == 1 }
            return SetupResult(issues: first ? [
                SetupIssue(
                    step: .tools, title: "Missing", explanation: "Install", commands: "install", alternative: "",
                ),
            ] : [], agents: [.codexCLI])
        }, defaults: defaults)
        #expect(model.isReady)
        await model.checkOnLaunch()
        #expect(model.isReady == false)
        #expect(model.currentIssue?.step == .tools)
        await model.checkOnLaunch()
        #expect(attempts.withLock { $0 } == 1)
        await model.recheck()
        #expect(model.isReady)
        #expect(model.issues.isEmpty)
        #expect(model.agents == [.codexCLI])
        #expect(attempts.withLock { $0 } == 2)
    }
}
