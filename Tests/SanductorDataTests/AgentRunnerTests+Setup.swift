import Foundation
@testable import SanductorData
import Testing

extension AgentRunnerTests {
    @Test(arguments: ["missing", "signed-out", "signed-in"])
    func `sign-in checks the first installed binary rather than any working copy`(native: String) async throws {
        let root = try TestSupport.temporaryDirectory("agent-probe")
        defer { try? FileManager.default.removeItem(atPath: root) }
        for directory in ["native", "homebrew"] {
            try FileManager.default.createDirectory(atPath: root + "/" + directory, withIntermediateDirectories: true)
            if directory == "native", native == "missing" {
                continue
            }
            let binary = root + "/" + directory + "/codex"
            try ("""
            #!/bin/sh
            [ "$1" = login ] && [ "$2" = status ] || exit 2
            echo \(directory) >> \((root + "/probed").shellQuoted)
            exit \(directory == "native" && native == "signed-out" ? 1 : 0)
            """).write(toFile: binary, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary)
        }
        let result = try await TestSupport.run(TestSupport.sudoLoginArguments([
            "/bin/zsh", "-fc", CodexRunner().authenticationCommand(
                directories: [root + "/native", root + "/homebrew"], arguments: ["login", "status"],
            ),
        ]))
        #expect(result.standardOutput.contains("agent=codex") == (native != "signed-out"))
        #expect(result.standardError.contains("sign-in check failed") == (native == "signed-out"))
        #expect(try String(contentsOfFile: root + "/probed", encoding: .utf8)
            == (native == "missing" ? "homebrew\n" : "native\n"))
    }
}
