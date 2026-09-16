@testable import AgentIDEData
import Foundation
import Testing

struct StyleScriptTests {
    @Test(arguments: ["", "shell", "github_actions", "docs", "swift"])
    func `a failing step fails the style run`(family: String) async throws {
        let root = try TestSupport.temporaryDirectory("style-script")
        defer { try? FileManager.default.removeItem(atPath: root) }
        try FileManager.default.createDirectory(atPath: root + "/script", withIntermediateDirectories: true)
        let source = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "script/style")
        // A failing first step followed by success must not be lost
        // to Bash's conditional errexit rules around a subshell.
        let script = try String(contentsOf: source, encoding: .utf8).replacing(
            "families=(shell github_actions docs swift)",
            with: """
            run_family() {
              test "$1" != "$FAILING_FAMILY"
              true
            }
            families=(shell github_actions docs swift)
            """,
        )
        try script.write(toFile: root + "/script/style", atomically: true, encoding: .utf8)

        let result = try await FoundationProcessRunner().run(
            ["/bin/bash", root + "/script/style"],
            workingDirectory: root,
            environment: ["FAILING_FAMILY": family],
        )

        #expect(result.succeeded == family.isEmpty)
    }
}
