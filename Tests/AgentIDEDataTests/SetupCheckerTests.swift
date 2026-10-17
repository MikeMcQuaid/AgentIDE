@testable import AgentIDEData
import Foundation
import Testing

struct SetupCheckerTests {
    @Test
    func `missing tools are listed together before any credential or sandbox checks`() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.runner.missing.withLock { $0 = "brew\ngh\nherdr\nrg\nsv\n" }
        let result = await fixture.checker.check(verifyOnline: true)
        #expect(result.issues.count == 1)
        #expect(result.issues.first?.explanation.contains("brew, gh, herdr, rg, sv") == true)
        #expect(result.issues.first?.explanation.contains("https://brew.sh") == true)
        #expect(result.issues.first?.alternative.isEmpty == true)
        #expect(result.issues.first?.commands == "brew install git gh herdr ripgrep sandvault")
        #expect(fixture.runner.commands.withLock { $0.count } == 1)
    }

    @Test
    func `github setup needs only HTTPS web login`() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.runner.failure.withLock { $0 = "credentials" }
        let result = await fixture.checker.check(verifyOnline: true)
        let issue = try #require(result.issues.first { $0.title == "Connect your GitHub account" })
        #expect(issue.commands == "gh auth login --hostname github.com --git-protocol https --web")
        #expect(issue.alternative.contains("Yes"))
    }

    @Test
    func `agent probes survive the sudo login shell and use the sandbox environment`() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        for (path, script) in [
            (fixture.paths.sandboxHome + "/configure", "exit 99"),
            (fixture.paths.sandboxHome + "/.local/bin/claude", "exit 1"),
            (fixture.paths.userTemplateDirectory + "/bin/codex", """
            [ "$PWD" = "$HOME" ] && [ -d "$TMPDIR" ] && [ -w "$TMPDIR" ] || exit 1
            [ -f "$HOME/signed-in" ] || { echo 'Not logged in' >&2; exit 1; }
            [ "$1" = login ] && [ "$2" = status ]
            """),
        ] {
            try FileManager.default.createDirectory(
                at: URL(filePath: path).deletingLastPathComponent(), withIntermediateDirectories: true,
            )
            try ("#!/bin/sh\n" + script + "\n").write(toFile: path, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        }
        _ = await fixture.checker.check(verifyOnline: false)
        let command = try #require(fixture.runner.commands.withLock { $0.first { $0.first == "sudo" }?.last })
        for signedIn in [false, true] {
            if signedIn {
                try Data().write(to: URL(filePath: fixture.paths.sandboxHome + "/signed-in"))
            }
            let result = try await FoundationProcessRunner().run(
                TestSupport.sudoLoginArguments(["/bin/zsh", "-fc", command]),
                workingDirectory: fixture.root,
                environment: ["HOME": fixture.paths.sandboxHome, "TMPDIR": fixture.root + "/missing"],
            )
            #expect(result.succeeded)
            #expect(result.standardOutput.contains("no-legacy"))
            #expect(result.standardOutput.contains("agent=codex") == signedIn)
            #expect(result.standardError.contains("Not logged in") == (signedIn == false))
        }
    }

    @Test(arguments: [false, true])
    func `tool probe requires Homebrew even when other tools are installed`(hasHomebrew: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.runner.missing.withLock { $0 = "brew\n" }
        _ = await fixture.checker.check(verifyOnline: false)
        let probe = try #require(fixture.runner.commands.withLock { $0.first })
        for tool in ["git", "gh", "herdr", "rg", "sv"] + (hasHomebrew ? ["brew"] : []) {
            try FileManager.default.createSymbolicLink(
                atPath: fixture.root + "/" + tool, withDestinationPath: "/usr/bin/true",
            )
        }
        let result = try await FoundationProcessRunner().run(
            probe, workingDirectory: nil, environment: ["PATH": fixture.root],
        )
        #expect(result.succeeded)
        #expect(result.standardOutput == (hasHomebrew ? "" : "brew\n"))
    }

    @Test(arguments: [false, true])
    func `only initial setup contacts GitHub`(online: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let result = await fixture.checker.check(verifyOnline: online)
        #expect(result.issues.isEmpty)
        #expect(result.agents == [.codexCLI])
        #expect(FileManager.default.fileExists(atPath: fixture.paths.repositoriesDirectory))
        #expect(FileManager.default.fileExists(atPath: fixture.paths.userTemplateDirectory + "/.claude/settings.json"))
        let commands = fixture.runner.commands.withLock { $0 }
        #expect(commands.contains { $0.first == "gh" && $0.contains("api") } == online)
        let sandbox = try #require(commands.first { $0.first == "sudo" })
        #expect(sandbox.contains("--non-interactive"))
        #expect(sandbox.last?.contains("auth' 'status") == true)
        #expect(sandbox.last?.contains("login' 'status") == true)
        #expect(sandbox.last?.contains("~/configure;") == false)
    }

    @Test(arguments: ["identity", "credentials", "sandbox", "agent", "keychain", "network"])
    func `unmet prerequisites block until repaired`(failure: String) async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.runner.failure.withLock { $0 = failure }
        let failed = await fixture.checker.check(verifyOnline: true)
        #expect(failed.issues.isEmpty == false)
        fixture.runner.failure.withLock { $0 = "" }
        let repaired = await fixture.checker.check(verifyOnline: true)
        #expect(repaired.issues.isEmpty)
    }

    @Test(arguments: [false, true])
    func `signing availability never blocks setup`(configured: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.runner.failure.withLock { $0 = configured ? "" : "signing" }
        let result = await fixture.checker.check(verifyOnline: false)
        #expect(result.issues.isEmpty)
        #expect(result.signingConfigured == configured)
    }

    @Test(arguments: ["missing-key", "missing-private-key", "missing-signer", "ready"])
    func `SSH signing needs an available key and signer`(state: String) async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let key = fixture.root + "/signing"
        fixture.runner.gitConfiguration.withLock { configuration in
            configuration = "user.name Test\nuser.email test@example.com\ngpg.format ssh\n"
                + "user.signingkey " + key + ".pub\n"
        }
        if state != "missing-key" {
            try Data("ssh-ed25519 test".utf8).write(to: URL(filePath: key + ".pub"))
        }
        if state == "ready" || state == "missing-signer" {
            try Data().write(to: URL(filePath: key))
        }
        fixture.runner.failure.withLock { $0 = state == "missing-signer" ? "signing" : "" }
        let result = await fixture.checker.check(verifyOnline: false)
        #expect(result.issues.isEmpty)
        #expect(result.signingConfigured == (state == "ready"))
    }

    @Test
    func `running in the sandbox never accesses host credentials`() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let result = await SetupChecker(service: fixture.service, isInsideSandbox: true).check(verifyOnline: true)
        #expect(result.issues.isEmpty == false)
        #expect(fixture.runner.commands.withLock { $0.isEmpty })
    }

    @Test
    func `an absent shared workspace is not created before sandvault setup`() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        try FileManager.default.removeItem(atPath: fixture.paths.sharedWorkspace)
        let result = await fixture.checker.check(verifyOnline: false)
        #expect(result.issues.contains { $0.title == "Set up sandvault" })
        #expect(FileManager.default.fileExists(atPath: fixture.paths.sharedWorkspace) == false)
        #expect(fixture.runner.commands.withLock { $0.contains { $0.first == "sudo" } } == false)
    }

    @Test
    func `signing can be explicitly disabled`() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.runner.failure.withLock { $0 = "signing" }
        var checker = SetupChecker(service: fixture.service, isInsideSandbox: false, requiresSignedCommits: false)
        checker.agentBinaryDirectories = []
        let result = await checker.check(verifyOnline: false)
        #expect(result.issues.isEmpty)
    }

    @Test
    func `generated sandbox and recovery commands are valid shell`() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.runner.failure.withLock { $0 = "signing" }
        let result = await fixture.checker.check(verifyOnline: false)
        let command = try #require(fixture.runner.commands.withLock { $0.first { $0.first == "sudo" }?.last })
        for script in [command] + result.issues.map(\.commands) {
            let syntax = try await TestSupport.run(["/bin/zsh", "-n", "-c", script])
            #expect(syntax.succeeded, "\(syntax.standardError)")
        }
    }

    @Test
    func `setup removes agent quarantine before checking sign-in`() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        try FileManager.default.createDirectory(atPath: fixture.root + "/bin", withIntermediateDirectories: true)
        let binary = fixture.root + "/bin/codex"
        try Data().write(to: URL(filePath: binary))
        let marker = "0083;00000000;test;"
        try #require(marker.withCString { value in
            unsafe setxattr(binary, "com.apple.quarantine", value, marker.utf8.count, 0, 0) == 0
        })
        _ = await fixture.checker.check(verifyOnline: false)
        #expect(unsafe getxattr(binary, "com.apple.quarantine", nil, 0, 0, 0) < 0)
    }
}
