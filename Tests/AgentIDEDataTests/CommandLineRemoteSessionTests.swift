@testable import AgentIDEData
import AgentIDEDomain
@testable import AgentIDERemote
import Foundation
import Testing

struct CommandLineRemoteSessionTests {
    // MARK: Internal

    @Test
    func `the bundled command declares the phone capabilities`() async throws {
        let shared = try TestSupport.temporaryDirectory("phone")
        defer { try? FileManager.default.removeItem(atPath: shared) }
        let result = try await run("--help", input: "", shared: shared)
        #expect(result.succeeded)
        try RemoteHerdr.validateCommandHelp(result.standardError)
    }

    @Test
    func `remote creation reads a multiline prompt without interactive questions`() async throws {
        let shared = try TestSupport.temporaryDirectory("phone")
        defer { try? FileManager.default.removeItem(atPath: shared) }
        try await TestSupport.makeRepository(at: shared + "/repositories/repo")
        let prompt = "First line\nSecond line with 'quotes' and $(touch should-not-exist)"
        let result = try await run(
            "new --repository repo --agent codex --model gpt-5 --effort high --no-attach",
            input: prompt,
            shared: shared,
        )
        #expect(result.succeeded)
        let branch = SessionName.slug(String(prompt.prefix(40))).replacing("-", with: "_")
        #expect(result.standardOutput.hasPrefix("branch=" + branch + "\n"))
        #expect(result.standardError.contains("Repository:") == false)
        #expect(result.standardOutput.contains("label=agentide--repo--"))
        #expect(result.standardOutput.contains("codex --model gpt-5 -c model_reasoning_effort=high"))
    }

    @Test(arguments: ["my repo", "café", "repo ' $(false)"])
    func `remote creation accepts repository names from the listing`(repository: String) async throws {
        let shared = try TestSupport.temporaryDirectory("phone")
        defer { try? FileManager.default.removeItem(atPath: shared) }
        try await TestSupport.makeRepository(at: shared + "/repositories/" + repository)
        let listing = try await run("repositories", input: "", shared: shared)
        #expect(listing.standardOutput == repository + "\n")
        let result = try await run(
            "new --repository " + repository.shellQuoted + " --agent codex --no-attach",
            input: "A prompt",
            shared: shared,
        )
        #expect(result.succeeded)
        #expect(result.standardOutput.contains("worktree=" + shared + "/worktrees/" + repository + "/a_prompt\n"))
        #expect(result.standardOutput.contains(
            "label=agentide--" + SessionName.slug(repository) + "--a-prompt--codex\n",
        ))
    }

    @Test(arguments: [".", "..", "../outside", "/outside", "repo/../outside", "missing"])
    func `remote creation refuses anything except an existing repository`(repository: String) async throws {
        let shared = try TestSupport.temporaryDirectory("phone")
        defer { try? FileManager.default.removeItem(atPath: shared) }
        let result = try await run(
            "new --repository " + repository.shellQuoted + " --agent claude --no-attach",
            input: "A prompt",
            shared: shared,
        )
        #expect(result.succeeded == false)
        #expect(FileManager.default.fileExists(atPath: shared + "/worktrees") == false)
    }

    @Test(arguments: ["repo", "../outside"])
    func `remote creation refuses symlinked repositories`(destination: String) async throws {
        let shared = try TestSupport.temporaryDirectory("phone")
        defer { try? FileManager.default.removeItem(atPath: shared) }
        try await TestSupport.makeRepository(at: shared + "/repositories/repo")
        try await TestSupport.makeRepository(at: shared + "/outside")
        try FileManager.default.createSymbolicLink(
            atPath: shared + "/repositories/alias", withDestinationPath: destination,
        )
        let result = try await run(
            "new --repository alias --agent codex --no-attach", input: "A prompt", shared: shared,
        )
        #expect(result.succeeded == false)
        #expect(result.standardError.contains("repository must be inside"))
    }

    @Test
    func `repository listing includes only existing checkouts`() async throws {
        let shared = try TestSupport.temporaryDirectory("phone")
        defer { try? FileManager.default.removeItem(atPath: shared) }
        try await TestSupport.makeRepository(at: shared + "/repositories/repo")
        try FileManager.default.createSymbolicLink(
            atPath: shared + "/repositories/alias", withDestinationPath: "repo",
        )
        try await TestSupport.makeRepository(at: shared + "/outside")
        try FileManager.default.createSymbolicLink(
            atPath: shared + "/repositories/external", withDestinationPath: "../outside",
        )
        try FileManager.default.createDirectory(
            atPath: shared + "/repositories/empty", withIntermediateDirectories: true,
        )
        let result = try await run("repositories", input: "", shared: shared)
        #expect(result.succeeded)
        #expect(result.standardOutput == "repo\n")
    }

    @Test
    func `listing and creation follow the directories the app published`() async throws {
        let shared = try TestSupport.temporaryDirectory("phone")
        defer { try? FileManager.default.removeItem(atPath: shared) }
        try await TestSupport.makeRepository(at: shared + "/projects/repo")
        try await TestSupport.makeRepository(at: shared + "/repositories/stale")
        try publish(
            ["repositories-directory=" + shared + "/projects", "worktrees-directory=" + shared + "/trees"],
            in: shared,
        )

        let listing = try await run("repositories", input: "", shared: shared)
        #expect(listing.standardOutput == "repo\n")
        let result = try await run("new --repository repo --agent codex --no-attach", input: "A prompt", shared: shared)
        #expect(result.succeeded)
        #expect(result.standardOutput.contains("worktree=" + shared + "/trees/repo/a_prompt\n"))
        let stale = try await run("new --repository stale --agent codex --no-attach", input: "A prompt", shared: shared)
        #expect(stale.succeeded == false)
    }

    @Test(arguments: [".", "..", "../outside", "/outside", "repo/../outside", "missing"])
    func `relocated creation refuses anything except an existing repository`(repository: String) async throws {
        let shared = try TestSupport.temporaryDirectory("phone")
        defer { try? FileManager.default.removeItem(atPath: shared) }
        // Every traversal lands on a real checkout, so only the
        // containment check can refuse it.
        for checkout in ["/projects/repo", "/projects/outside", "/outside"] {
            try await TestSupport.makeRepository(at: shared + checkout)
        }
        try publish(["repositories-directory=" + shared + "/projects"], in: shared)
        let result = try await run(
            "new --repository " + repository.shellQuoted + " --agent claude --no-attach",
            input: "A prompt",
            shared: shared,
        )
        #expect(result.succeeded == false)
    }

    @Test
    func `without published directories the shared workspace's own are used`() async throws {
        let shared = try TestSupport.temporaryDirectory("phone")
        defer { try? FileManager.default.removeItem(atPath: shared) }
        try await TestSupport.makeRepository(at: shared + "/repositories/repo")
        try publish(["agent=codex", "repositories=repo"], in: shared)

        let listing = try await run("repositories", input: "", shared: shared)
        #expect(listing.standardOutput == "repo\n")
        let result = try await run("new --repository repo --agent codex --no-attach", input: "A prompt", shared: shared)
        #expect(result.standardOutput.contains("worktree=" + shared + "/worktrees/repo/a_prompt\n"))
    }

    // MARK: Private

    /// Writes the lines the app would publish for the command.
    private func publish(_ lines: [String], in shared: String) throws {
        try FileManager.default.createDirectory(atPath: shared + "/agentide", withIntermediateDirectories: true)
        try (lines.joined(separator: "\n") + "\n").write(
            toFile: shared + "/agentide/session-defaults", atomically: true, encoding: .utf8,
        )
    }

    private func run(_ arguments: String, input: String, shared: String) async throws -> ProcessResult {
        let command = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "bin/agentide")
            .path
        return try await FoundationProcessRunner().run(
            ["/bin/sh", "-c", "printf '%s' " + input.shellQuoted + " | " + command.shellQuoted + " " + arguments],
            workingDirectory: nil,
            environment: ["SHARED_WORKSPACE": shared, "AGENTIDE_DRY_RUN": "1", "AGENTIDE_EDITS": shared + "/edits"],
        )
    }
}
