@testable import AgentIDEData
import Foundation
import Testing

struct HerdrStartupTests {
    @Test
    func `server startup inherits native agent paths from the sandbox profile`() async throws {
        let root = try TestSupport.temporaryDirectory("native-startup")
        defer { try? FileManager.default.removeItem(atPath: root) }
        try FileManager.default.createDirectory(atPath: root + "/.local/bin", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: root + "/fallback", withIntermediateDirectories: true)
        for (name, content) in [
            ("configure", "#!/bin/sh\nexit 0"),
            (".zshenv", ""),
            (".zprofile", "export PATH=\"${HOME}/.local/bin:${PATH}\""),
            (".zshrc", ""),
            (".local/bin/codex", "#!/bin/sh\necho native"),
            ("fallback/codex", "#!/bin/sh\nexit 99"),
        ] {
            try content.write(toFile: root + "/" + name, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root + "/" + name)
        }
        let recorder = RecordingRunner()
        try await HerdrClient(
            runner: recorder,
            launcher: SandvaultLauncher(hostUser: "test"),
            isInsideSandbox: false,
            configHome: root + "/config",
        ).ensureServer()
        let command = try #require(recorder.commands.first)
        let payload = try #require(command.last)
        let path = try #require(command.first { $0.hasPrefix("PATH=") })
        let result = try await FoundationProcessRunner().run(
            TestSupport.sudoLoginArguments([
                "/bin/zsh", "-fc", """
                herdr() {
                    if [[ "${1}" == api ]]; then [[ -f "${HOME}/started" ]]; return; fi;
                    codex > "${HOME}/agent" && touch "${HOME}/started";
                };
                """ + payload,
            ]),
            workingDirectory: root,
            environment: [
                "HOME": root, "ZDOTDIR": root, "PATH": root + "/fallback:" + path.dropFirst("PATH=".count),
            ],
        )
        #expect(result.succeeded, "\(result.standardError)")
        #expect(try String(contentsOfFile: root + "/agent", encoding: .utf8) == "native\n")
    }
}
