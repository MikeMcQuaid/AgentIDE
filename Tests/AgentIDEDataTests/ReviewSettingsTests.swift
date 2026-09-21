import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

struct ReviewSettingsTests {
    @Test
    func `review preferences are independent per agent and read afresh`() throws {
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("session-model", forKey: "agentModel")
        defaults.set("session-effort", forKey: "agentEffort")
        #expect(AppSettings.reviewOptions(for: .claudeCode, defaults: defaults) == AgentLaunchOptions())
        defaults.set("fable", forKey: AppSettings.reviewModelKey(for: .claudeCode))
        defaults.set("max", forKey: AppSettings.reviewEffortKey(for: .claudeCode))
        defaults.set("gpt-5.6-sol", forKey: AppSettings.reviewModelKey(for: .codexCLI))
        defaults.set("high", forKey: AppSettings.reviewEffortKey(for: .codexCLI))
        #expect(AppSettings.reviewOptions(for: .claudeCode, defaults: defaults)
            == AgentLaunchOptions(model: "fable", effort: "max"))
        #expect(AppSettings.reviewOptions(for: .codexCLI, defaults: defaults)
            == AgentLaunchOptions(model: "gpt-5.6-sol", effort: "high"))
        defaults.set("medium", forKey: AppSettings.reviewEffortKey(for: .codexCLI))
        #expect(AppSettings.reviewOptions(for: .codexCLI, defaults: defaults).effort == "medium")
        defaults.set("", forKey: AppSettings.reviewModelKey(for: .codexCLI))
        #expect(AppSettings.reviewOptions(for: .codexCLI, defaults: defaults).model == nil)
        #expect(defaults.string(forKey: "agentModel") == "session-model")
        #expect(defaults.string(forKey: "agentEffort") == "session-effort")
    }

    @Test(arguments: AgentKind.allCases)
    func `review model and effort reach the CLI as literal arguments`(agent: AgentKind) async throws {
        let directory = try TestSupport.temporaryDirectory("review-options")
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let executable = directory + "/reviewer"
        try "#!/bin/sh\nprintf '%s\\n' \"$@\"\n"
            .write(toFile: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable)
        let schema = directory + "/schema.json"
        try "{}".write(toFile: schema, atomically: true, encoding: .utf8)
        let marker = directory + "/injected"
        let model = "model 'quoted' $(touch " + marker + ")"
        let effort = "high; touch " + marker
        let runner: any AgentRunner = agent == .claudeCode ? ClaudeCodeRunner() : CodexRunner()
        let result = try await TestSupport.run([
            "/bin/zsh", "-c", runner.reviewCommand(
                executable: executable,
                promptFile: "/dev/null",
                schemaFile: schema,
                options: AgentLaunchOptions(model: model, effort: effort),
            ),
        ])
        let arguments = result.standardOutput.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let modelFlag = try #require(arguments.firstIndex(of: "--model"))
        #expect(arguments[modelFlag + 1] == model)
        if agent == .claudeCode {
            let effortFlag = try #require(arguments.firstIndex(of: "--effort"))
            #expect(arguments[effortFlag + 1] == effort)
            let toolsFlag = try #require(arguments.firstIndex(of: "--tools"))
            #expect(arguments[toolsFlag + 1].isEmpty)
        } else {
            #expect(arguments.contains("model_reasoning_effort=" + effort))
            let sandboxFlag = try #require(arguments.firstIndex(of: "--sandbox"))
            #expect(arguments[sandboxFlag + 1] == "read-only")
        }
        #expect(FileManager.default.fileExists(atPath: marker) == false)
    }
}
