@testable import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

/// `agentide new` makes sessions the app has to recognise, so the
/// names, paths and launch command it computes are pinned to the
/// app's own, and its questions are answered the way a phone
/// answers them: mostly by pressing Enter.
struct CommandLineSessionTests {
    // MARK: Internal

    @Test
    func `pressing enter through the questions names the session as the app would`() async throws {
        let prompt = "Fix the flaky Formula test, please!"
        let shared = try Self.makeWorkspace()

        let plan = try await Self.plan(answering: "\n\n\n\n" + prompt + "\n", in: shared)

        let branch = SessionName.slug(String(prompt.prefix(40))).replacing("-", with: "_")
        let label = SessionName.make(repository: "brew", branch: branch, agent: .claudeCode)
        #expect(plan["branch"] == branch)
        #expect(plan["label"] == label)
        #expect(plan["worktree"] == shared + "/worktrees/brew/" + branch)
        #expect(plan["prompt"] == shared + "/agentide/prompts/" + label + ".md")
        // The window's own last choices, which the app publishes.
        #expect(plan["command"]?.hasPrefix("claude --model opus-5 --effort high ") == true)
    }

    @Test
    func `an answer that is neither a number nor a name is asked again`() async throws {
        let shared = try Self.makeWorkspace()

        let plan = try await Self.plan(answering: "9\nnonsense\n2\n\n\n\n\nfix it\n", in: shared)

        // The rejected answers cost nothing: the run reached the same
        // session the accepted ones name.
        #expect(plan["label"] == SessionName.make(repository: "brew", branch: "fix_it", agent: .claudeCode))
    }

    @Test
    func `choices are picked by number, and each agent spells its own effort`() async throws {
        let shared = try Self.makeWorkspace()

        let plan = try await Self.plan(answering: "2\n2\n1\n1\ntidy the docs\n", in: shared)

        #expect(plan["label"] == SessionName.make(repository: "brew", branch: "tidy_the_docs", agent: .codexCLI))
        #expect(plan["command"]?.contains("-c model_reasoning_effort=minimal") == true)
    }

    @Test
    func `a choice nothing was made before insists, and is remembered after`() async throws {
        let shared = try Self.makeWorkspace()
        let file = shared + "/agentide/session-defaults"
        // Nothing chosen for Codex yet: Enter is refused until its
        // effort and model are picked.
        let plan = try await Self.plan(answering: "\n2\n\n1\n1\ntidy the docs\n", in: shared)

        #expect(plan["command"]?.contains("--model gpt-5.6-sol") == true)
        #expect(plan["command"]?.contains("-c model_reasoning_effort=minimal") == true)

        // What was chosen is what the next session, in either
        // surface, comes back to.
        let kept = try String(contentsOfFile: file, encoding: .utf8)
        #expect(kept.contains("codex-model=gpt-5.6-sol"))
        #expect(kept.contains("codex-effort=minimal"))
        #expect(kept.contains("agent=codex"))
        // Everything else in the file survives the write.
        #expect(kept.contains("claude-models=opus-5 sonnet-5"))
    }

    @Test
    func `a narrow terminal lists one option per line`() async throws {
        let shared = try Self.makeWorkspace()
        let narrow = try await Self.questions(answering: "\n\n\n\nhello\n", columns: 12, in: shared)
        #expect(narrow.contains("1 AgentIDE\n2 brew\n"))
        let wide = try await Self.questions(answering: "\n\n\n\nhello\n", columns: 200, in: shared)
        #expect(wide.contains("1 AgentIDE  2 brew"))
    }

    // MARK: Private

    /// The command in the checkout, which is the copy the app bundles
    /// and installs into the shared workspace.
    private static let command = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "bin/agentide")
        .path

    /// What the command asks, given a terminal width and answers.
    private static func questions(answering answers: String, columns: Int, in shared: String) async throws -> String {
        let script = "printf '%s' " + answers.shellQuoted + " | " + command.shellQuoted + " new"
        let result = try await TestSupport.run([
            "/usr/bin/env",
            "SHARED_WORKSPACE=" + shared,
            "AGENTIDE_DRY_RUN=1",
            "COLUMNS=" + String(columns),
            "/bin/sh",
            "-c",
            script,
        ])
        try #require(result.succeeded)
        return result.standardError
    }

    /// A shared workspace holding one repository and the defaults the
    /// app publishes from the window.
    private static func makeWorkspace() throws -> String {
        let shared = try TestSupport.temporaryDirectory("command-line")
        try FileManager.default.createDirectory(
            atPath: shared + "/repositories/brew/.git",
            withIntermediateDirectories: true,
        )
        try FileManager.default.createDirectory(
            atPath: shared + "/agentide",
            withIntermediateDirectories: true,
        )
        try """
        repository=brew
        agent=claude
        repositories=AgentIDE brew
        claude-models=opus-5 sonnet-5
        claude-efforts=low medium high xhigh max
        claude-model=opus-5
        claude-effort=high
        codex-models=gpt-5.6-sol gpt-5.5
        codex-efforts=minimal low medium high xhigh

        """.write(toFile: shared + "/agentide/session-defaults", atomically: true, encoding: .utf8)
        return shared
    }

    /// What the command says it would make, given those answers.
    private static func plan(answering answers: String, in shared: String) async throws -> [String: String] {
        let script = "printf '%s' " + answers.shellQuoted + " | " + command.shellQuoted + " new"
        let result = try await TestSupport.run([
            "/usr/bin/env",
            "SHARED_WORKSPACE=" + shared,
            "AGENTIDE_DRY_RUN=1",
            "/bin/sh",
            "-c",
            script,
        ])
        try #require(result.succeeded)
        return result.standardOutput.split(separator: "\n").reduce(into: [:]) { plan, line in
            let parts = line.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                plan[String(parts[0])] = String(parts[1])
            }
        }
    }
}
