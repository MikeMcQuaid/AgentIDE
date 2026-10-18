@testable import AgentIDEData
@testable import DashboardFeature
import Foundation
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
        #expect(reopened.isReady == false)
        await reopened.recheck()
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

    @Test
    func `slow checks yield the main actor and reject duplicate rechecks`() async throws {
        let suite = "setup-test-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
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
        #expect(model.isReady == false)
        await model.recheck()
        waiting.withLock { $0 }?.resume(returning: SetupResult(issues: [], agents: [.codexCLI]))
        await task.value
        #expect(model.isReady)
        #expect(model.isChecking == false)
    }
}
