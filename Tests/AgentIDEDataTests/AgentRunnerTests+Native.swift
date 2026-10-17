@testable import AgentIDEData
import Foundation
import Testing

extension AgentRunnerTests {
    @Test(arguments: [false, true])
    func `claude launches and resumes select an existing native install`(native: Bool) async throws {
        let root = try TestSupport.temporaryDirectory("native-agent")
        defer { try? FileManager.default.removeItem(atPath: root) }
        try FileManager.default.createDirectory(atPath: root + "/.local/bin", withIntermediateDirectories: true)
        if native {
            let binary = root + "/.local/bin/claude"
            try Data("#!/bin/sh\n".utf8).write(to: URL(filePath: binary))
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary)
        }
        let runner = ClaudeCodeRunner()
        for command in [
            runner.launchCommand(extraArguments: "", promptFile: nil),
            runner.resumeCommand(resumeID: "test", extraArguments: ""),
        ] {
            let result = try await TestSupport.run([
                "/bin/zsh", "-fc",
                "claude() { echo native=${SV_NATIVE_INSTALL:-false}; }; " + command.replacing("$HOME", with: root),
            ])
            #expect(result.succeeded)
            #expect(result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "native=\(native)")
        }
    }
}
