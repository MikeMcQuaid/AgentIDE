import Foundation
@testable import SanductorData
import SanductorDomain
import Testing

struct LegacySandboxMigrationTests {
    @Test
    func `the new session name attaches to an existing server without losing its workspace`() async throws {
        let root = try TestSupport.configHome()
        defer {
            TestSupport.runSync(
                ["/bin/zsh", "-fc", "cd " + root.shellQuoted + " && herdr server stop"],
                environment: ["XDG_CONFIG_HOME": "c", "HERDR_SESSION": "agentide", "HOME": root],
            )
            try? FileManager.default.removeItem(atPath: root)
        }
        let runner = FoundationProcessRunner()
        let environment = [
            "HOME": root, "XDG_CONFIG_HOME": "c", "HERDR_SESSION": "agentide", "SHARED_WORKSPACE": root + "/shared",
        ]
        let started = try await runner.run(
            [
                "/bin/zsh", "-fc", """
                set -eu
                ln -s /usr/bin/true configure
                mkdir -p shared/agentide
                printf '%s' 'old prompt' >shared/agentide/prompt
                herdr server &>server.log &!
                for _ in {1..50}; do
                  herdr api snapshot &>/dev/null &&
                    exec herdr workspace create --cwd "$HOME" --label agentide--repo--branch--claude
                  sleep 0.1
                done
                cat server.log >&2; exit 1
                """,
            ],
            workingDirectory: root,
            environment: environment,
        )
        try #require(started.succeeded, "\(started.standardError)")
        let previous = try await runner.run(
            ["herdr", "api", "snapshot"], workingDirectory: root, environment: environment,
        )
        let migrated = try await runner.run(
            TestSupport.sudoLoginArguments(["/bin/zsh", "-fc", LegacyMigration.sandboxScript]),
            workingDirectory: root,
            environment: environment,
        )
        try #require(migrated.succeeded, "\(migrated.standardError)")
        var renamed = environment
        renamed["HERDR_SESSION"] = "sanductor"
        let current = try await runner.run(["herdr", "api", "snapshot"], workingDirectory: root, environment: renamed)
        try #require(current.succeeded, "\(current.standardError)")
        let oldSnapshot = try HerdrSnapshot.decode(Data(previous.standardOutput.utf8))
        let newSnapshot = try HerdrSnapshot.decode(Data(current.standardOutput.utf8))
        #expect(newSnapshot.workspaces.map(\.workspaceID) == oldSnapshot.workspaces.map(\.workspaceID))
        #expect(newSnapshot.workspaces.contains { $0.label == "agentide--repo--branch--claude" })
        #expect(try String(contentsOfFile: root + "/shared/sanductor/prompt", encoding: .utf8) == "old prompt")
    }

    @Test
    func `migration uses guest paths and preserves existing files on retry`() async throws {
        let root = try TestSupport.temporaryDirectory("guest-migration")
        defer { try? FileManager.default.removeItem(atPath: root) }
        try await TestSupport.run(
            [
                "/bin/zsh", "-fc", """
                set -eu
                ln -s /usr/bin/true configure
                mkdir -p shared/{agentide,sanductor} .config/herdr/sessions/agentide
                printf '%s' 'old prompt' >shared/agentide/prompt
                printf '%s' 'new prompt' >shared/sanductor/prompt
                printf '%s' 'missing prompt' >shared/agentide/missing
                """,
            ],
            in: root,
        )
        for _ in 0 ..< 2 {
            let migrated = try await FoundationProcessRunner().run(
                TestSupport.sudoLoginArguments([
                    "/usr/bin/env", "-i", "HOME=" + root, "SHARED_WORKSPACE=" + root + "/shared",
                    "/bin/zsh", "-fc", LegacyMigration.sandboxScript,
                ]),
                workingDirectory: root,
                environment: ["HOME": root + "/host", "SHARED_WORKSPACE": root + "/host-shared"],
            )
            try #require(migrated.succeeded, "\(migrated.standardError)")
        }
        #expect(try FileManager.default.destinationOfSymbolicLink(
            atPath: root + "/.config/herdr/sessions/sanductor",
        ) == "agentide")
        #expect(try String(contentsOfFile: root + "/shared/sanductor/prompt", encoding: .utf8) == "new prompt")
        #expect(try String(contentsOfFile: root + "/shared/sanductor/missing", encoding: .utf8) == "missing prompt")
    }
}
