import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

// MARK: - PromptCaptureRunner

/// A fake agent that records its arguments and captures the pasted
/// prompt, standing in for a real CLI in integration tests.
struct PromptCaptureRunner: AgentRunner {
    var kind: AgentKind {
        .claudeCode
    }

    var scopesTranscriptsByWorkingDirectory: Bool {
        true
    }

    var models: [String] {
        ["fable"]
    }

    var efforts: [String] {
        ["max"]
    }

    var modelListingCommand: [String] {
        ["true"]
    }

    func launchCommand(extraArguments: String, promptFile: String?) -> String {
        let quoted = "'" + extraArguments.replacing("'", with: "'\\''") + "'"
        let prompt = promptFile.map { "cat '" + $0 + "' > agent-prompt.txt; " } ?? ""
        return "printf '%s' " + quoted + " > agent-arguments.txt; " + prompt + "cat > /dev/null"
    }

    func resumeCommand(resumeID: String, extraArguments _: String) -> String {
        "printf '%s' '" + resumeID + "' > agent-resumed.txt; cat > /dev/null"
    }

    func transcriptDirectory(workingDirectory: String, sandboxHome: String) -> String? {
        sandboxHome + "/transcripts/" + workingDirectory.replacing("/", with: "-")
    }

    func optionArguments(model: String?, effort: String?) -> String {
        var arguments = [String]()
        if let model {
            arguments += ["--model", model]
        }
        if let effort {
            arguments += ["--effort", effort]
        }
        return arguments.joined(separator: " ")
    }
}

// MARK: - SessionServiceIntegrationTests

/// Drives the whole core loop against real git, a private tmux
/// server and a temporary workspace: create, observe, delete and
/// resume.
struct SessionServiceIntegrationTests {
    @Test
    func `create session builds worktree, symlink, prompt and running pane`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }

        let name = try await world.service.createSession(
            repository: world.repository,
            prompt: "Do the thing",
            agent: .claudeCode,
            options: AgentLaunchOptions(model: "fable", effort: "max"),
        )
        #expect(SessionName.isAgentIDE(name))

        let overview = await world.service.overview()
        let item = try #require(overview.groups.first?.items.first { $0.worktree.branch.hasPrefix("do_the") })
        #expect(item.session?.name == name)
        #expect(item.session?.status == SessionStatus.running)
        let worktreePath = item.worktree.path

        let delivered = await TestSupport.poll {
            let prompt = try? String(contentsOfFile: worktreePath + "/agent-prompt.txt", encoding: .utf8)
            return prompt?.contains("Do the thing") ?? false
        }
        #expect(delivered)
        let arguments = try String(contentsOfFile: worktreePath + "/agent-arguments.txt", encoding: .utf8)
        #expect(arguments == "--model fable --effort max")

        let symlink = world.paths.friendlyWorktreesDirectory + "/repo/do_the_thing"
        let destination = try FileManager.default.destinationOfSymbolicLink(atPath: symlink)
        #expect(destination == worktreePath)
    }

    @Test
    func `deleting a worktree keeps its conversation in the repository sessions`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }

        let sessionName = try await world.service.createSession(
            repository: world.repository,
            prompt: "Doomed work",
            agent: .claudeCode,
        )
        let overview = await world.service.overview()
        let item = try #require(overview.groups.first?.items.first { $0.worktree.branch.hasPrefix("doomed_work") })
        let worktreePath = item.worktree.path
        try await world.service.closeSession(sessionName: sessionName, worktreePath: worktreePath)

        // A conversation the deleted worktree leaves behind.
        let runner = PromptCaptureRunner()
        let directory = try #require(runner.transcriptDirectory(
            workingDirectory: worktreePath,
            sandboxHome: world.paths.sandboxHome,
        ))
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let transcript = #"{"type":"user","message":{"content":[{"type":"text","text":"doomed"}]}}"# + "\n"
        try transcript.write(toFile: directory + "/doomed.jsonl", atomically: true, encoding: .utf8)

        try await world.service.deleteWorktree(item: item)
        #expect(FileManager.default.fileExists(atPath: worktreePath) == false)
        let after = await world.service.overview()
        #expect(after.groups.first?.items.contains { $0.worktree.path == worktreePath } == false)

        let sessions = await world.service.repositorySessions(for: world.repository)
        let kept = try #require(sessions.first { $0.session.id == "doomed" })
        #expect(kept.worktreePath == worktreePath)
        #expect(kept.session.title == "doomed")
    }

    @Test
    func `past sessions are discovered and resume into a new worktree with the transcript`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let sessionName = try await world.service.createSession(
            repository: world.repository,
            prompt: "original work",
            agent: .claudeCode,
        )
        let overview = await world.service.overview()
        let worktree = try #require(
            overview.groups.first?.items.first { $0.worktree.branch.hasPrefix("original_work") }?.worktree,
        )
        try await world.service.closeSession(sessionName: sessionName, worktreePath: worktree.path)

        // A finished conversation left behind by any tool.
        let runner = PromptCaptureRunner()
        let directory = try #require(runner.transcriptDirectory(
            workingDirectory: worktree.path,
            sandboxHome: world.paths.sandboxHome,
        ))
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let transcript = #"{"type":"user","message":{"content":[{"type":"text","text":"old prompt"}]}}"# + "\n"
        try transcript.write(toFile: directory + "/oldsession.jsonl", atomically: true, encoding: .utf8)

        let after = await world.service.overview()
        let item = try #require(after.groups.first?.items.first { $0.worktree.branch.hasPrefix("original_work") })
        let past = try #require(item.pastSessions.first { $0.id == "oldsession" })
        #expect(past.title == "old prompt")
        #expect(world.service.transcriptEntries(for: past).first?.text == "old prompt")

        _ = try await world.service.resumeInNewWorktree(past, repository: world.repository)
        let groups = await world.service.overview().groups
        let resumed = try #require(groups.first?.items.first { $0.worktree.branch.contains("resume") })
        let copied = try #require(runner.transcriptDirectory(
            workingDirectory: resumed.worktree.path,
            sandboxHome: world.paths.sandboxHome,
        ))
        #expect(FileManager.default.fileExists(atPath: copied + "/oldsession.jsonl"))
        try await TestSupport.poll(timeout: 10) {
            let marker = resumed.worktree.path + "/agent-resumed.txt"
            return (try? String(contentsOfFile: marker, encoding: .utf8)) == "oldsession"
        }
    }

    @Test
    func `orphaned conversations surface on the main checkout and repositories always list`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let sessionName = try await world.service.createSession(
            repository: world.repository,
            prompt: "doomed worktree",
            agent: .claudeCode,
        )
        let worktree = try #require(
            await world.service
                .overview()
                .groups
                .first?
                .items
                .first { $0.worktree.branch.hasPrefix("doomed_worktree") }?
                .worktree,
        )
        try await world.service.closeSession(sessionName: sessionName, worktreePath: worktree.path)

        let runner = PromptCaptureRunner()
        let directory = try #require(runner.transcriptDirectory(
            workingDirectory: worktree.path,
            sandboxHome: world.paths.sandboxHome,
        ))
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let transcript = #"{"type":"user","message":{"content":[{"type":"text","text":"lost work"}]}}"# + "\n"
        try transcript.write(toFile: directory + "/lostsession.jsonl", atomically: true, encoding: .utf8)

        // The worktree vanishes outside AgentIDE's lifecycle.
        try await TestSupport.runGit(["worktree", "remove", "--force", worktree.path], in: world.repository.path)

        let groups = await world.service.overview().groups
        let main = try #require(groups.first?.items.first)
        #expect(main.worktree.path == world.repository.path)
        let orphan = try #require(main.pastSessions.first { $0.id == "lostsession" })
        #expect(orphan.title == "lost work")
    }

    @Test
    func `search finds matches with ripgrep`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let target = world.repository.path + "/needle.swift"
        try "let haystack = 1\nlet needleValue = 2\n".write(toFile: target, atomically: true, encoding: .utf8)

        let hits = await world.service.search(worktreePath: world.repository.path, query: "needleValue")
        let hit = try #require(hits.first)
        #expect(hit.file == "needle.swift")
        #expect(hit.line == 2)
        #expect(hit.text.contains("needleValue"))
        #expect(await world.service.search(worktreePath: world.repository.path, query: "").isEmpty)
    }

    @Test
    func `lists files for the fuzzy finder`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        try FileManager.default.createDirectory(
            atPath: world.repository.path + "/deep",
            withIntermediateDirectories: true,
        )
        try "x\n".write(toFile: world.repository.path + "/deep/nested.swift", atomically: true, encoding: .utf8)

        let files = await world.service.listFiles(worktreePath: world.repository.path)
        #expect(files.contains("deep/nested.swift"))
        #expect(files.contains("README.md"))
    }

    @Test
    func `host shell command is an attach-or-create host tmux session named by repo and branch`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let worktree = Worktree(
            repositoryName: "My Repo",
            repositoryPath: world.repository.path,
            branch: "agent/fix thing",
            path: "/tmp/worktrees/0a1b2c/agent-fix-thing",
        )
        let command = world.service.hostShellCommand(worktree: worktree)

        #expect(command.first?.hasSuffix("tmux") == true)
        #expect(command.contains("new-session"))
        #expect(command.contains("-A"))
        let name = try #require(command.drop { $0 != "-s" }.dropFirst().first)
        // Names the repository and branch, never the worktree uuid;
        // the path digest keeps same-named repositories apart and
        // the dev prefix keeps tests away from production shells.
        let digest = SessionName.pathDigest(world.repository.path)
        #expect(name == "agentide-shell-dev--my-repo-" + digest + "--agent-fix-thing")
        let directoryFlag = try #require(command.firstIndex(of: "-c"))
        #expect(command[directoryFlag + 1] == worktree.path)
        // The host server reads no config file, so the wheel-scroll
        // options chain onto the command.
        #expect(command.contains("mouse"))
        #expect(command.contains("history-limit"))
    }
}

// MARK: - RepositoryPageIntegrationTests

/// The repository page's conversation browser and unread state, which
/// span worktrees rather than one session.
struct RepositoryPageIntegrationTests {
    @Test
    func `conversations from unrecorded worktrees in the repository's containers are listed`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }

        _ = try await world.service.createSession(
            repository: world.repository,
            prompt: "Anchor work",
            agent: .claudeCode,
        )
        let overview = await world.service.overview()
        let item = try #require(overview.groups.first?.items.first { $0.worktree.branch.hasPrefix("anchor_work") })
        let container = URL(filePath: item.worktree.path).deletingLastPathComponent().path

        // A conversation from a worktree another tool created and
        // deleted: nothing recorded anywhere, only its transcript.
        let ghostPath = container + "/agent-ghost"
        let runner = PromptCaptureRunner()
        let directory = try #require(runner.transcriptDirectory(
            workingDirectory: ghostPath,
            sandboxHome: world.paths.sandboxHome,
        ))
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let transcript = #"{"type":"user","message":{"content":[{"type":"text","text":"ghost"}]}}"# + "\n"
        try transcript.write(toFile: directory + "/ghost.jsonl", atomically: true, encoding: .utf8)

        let sessions = await world.service.repositorySessions(for: world.repository)
        let ghost = try #require(sessions.first { $0.session.id == "ghost" })
        #expect(ghost.worktreePath == ghostPath)
        #expect(ghost.session.title == "ghost")
    }

    @Test
    func `manual unread marks survive acknowledgement and clear on viewing`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }

        let path = world.repository.path
        let before = await world.service.overview()
        let main = try #require(before.groups.first?.items.first { $0.worktree.path == path })
        #expect(main.hasUnread == false)

        world.service.markUnread(worktreePath: path)
        let marked = await world.service.overview()
        #expect(marked.groups.first?.items.first { $0.worktree.path == path }?.hasUnread == true)

        // Staying on screen acknowledges activity without clearing
        // the deliberate mark.
        world.service.acknowledgeActivity(worktreePath: path)
        let acknowledged = await world.service.overview()
        #expect(acknowledged.groups.first?.items.first { $0.worktree.path == path }?.hasUnread == true)

        world.service.markSeen(worktreePath: path)
        let seen = await world.service.overview()
        #expect(seen.groups.first?.items.first { $0.worktree.path == path }?.hasUnread == false)
    }
}
