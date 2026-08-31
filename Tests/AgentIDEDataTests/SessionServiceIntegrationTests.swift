import AgentIDEData
import AgentIDEDomain
import Foundation
import Synchronization
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

    var defaultEffort: String? {
        nil
    }

    /// `command cat` sidesteps whatever the interactive shell the
    /// pane runs has aliased `cat` to.
    func launchCommand(extraArguments: String, promptFile: String?) -> String {
        let quoted = "'" + extraArguments.replacing("'", with: "'\\''") + "'"
        let prompt = promptFile.map { "command cat '" + $0 + "' > agent-prompt.txt; " } ?? ""
        return "printf '%s' " + quoted + " > agent-arguments.txt; " + prompt + "command cat > /dev/null"
    }

    func resumeCommand(resumeID: String, extraArguments _: String) -> String {
        "printf '%s' '" + resumeID + "' > agent-resumed.txt; command cat > /dev/null"
    }

    func transcriptDirectory(workingDirectory: String, sandboxHome: String) -> String? {
        sandboxHome + "/transcripts/" + ClaudeCodeRunner.projectDirectoryName(for: workingDirectory)
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

/// Drives the whole core loop against real git, a private herdr
/// server and a temporary workspace: create, observe, delete and
/// resume.
struct SessionServiceIntegrationTests {
    @Test
    func `create session builds worktree, prompt and running pane`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }

        let name = try await world.service.createSession(
            repository: world.repository,
            prompt: "Do the thing",
            agent: .claudeCode,
            options: AgentLaunchOptions(model: "fable", effort: "max"),
        )
        #expect(SessionName.isAgentIDE(name))

        // Polled, not read once: for the instant between the pane's
        // shell starting and it running the command, herdr reports
        // the shell as the foreground, which reads as finished. The
        // fake agent is not one herdr recognises, so nothing else
        // waits for it to settle.
        var item: WorktreeItem?
        let running = await TestSupport.poll {
            let overview = await world.service.overview()
            item = overview.groups.first?.items.first { $0.worktree.branch.hasPrefix("do_the") }
            return item?.session?.status == SessionStatus.running
        }
        #expect(running)
        let found = try #require(item)
        #expect(found.session?.name == name)
        let worktreePath = found.worktree.path

        let delivered = await TestSupport.poll {
            let prompt = try? String(contentsOfFile: worktreePath + "/agent-prompt.txt", encoding: .utf8)
            return prompt?.contains("Do the thing") ?? false
        }
        #expect(delivered)
        let arguments = try String(contentsOfFile: worktreePath + "/agent-arguments.txt", encoding: .utf8)
        #expect(arguments == "--model fable --effort max")

        // The canonical path is the readable one now; no symlink
        // stands beside it.
        #expect(worktreePath.hasSuffix("/worktrees/repo/do_the_thing"))
        #expect(FileManager.default.fileExists(atPath: world.paths.friendlyWorktreesDirectory) == false)
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
        await world.service.closeSession(sessionName: sessionName, worktree: item.worktree)

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
    func `merge cleanup refuses dirty and unmerged worktrees and removes merged ones`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }

        let sessionName = try await world.service.createSession(
            repository: world.repository,
            prompt: "Anchor work",
            agent: .claudeCode,
        )
        var overview = await world.service.overview()
        var item = try #require(overview.groups.first?.items.first { $0.worktree.branch.hasPrefix("anchor_work") })
        await world.service.closeSession(sessionName: sessionName, worktree: item.worktree)
        let git = GitClient(runner: FoundationProcessRunner())
        let base = "main"

        // Uncommitted changes: refused before anything runs.
        try "draft\n".write(toFile: item.worktree.path + "/draft.txt", atomically: true, encoding: .utf8)
        #expect(try await world.service.cleanUpMergedWorktree(item: item, baseRef: base) == .dirty)
        #expect(FileManager.default.fileExists(atPath: item.worktree.path))

        // A commit the base lacks: refused, since `-d` would refuse.
        try await git.commitAll(worktreePath: item.worktree.path, message: "Unmerged work")
        #expect(try await world.service.cleanUpMergedWorktree(item: item, baseRef: base) == .unmerged)
        #expect(FileManager.default.fileExists(atPath: item.worktree.path))

        // Once the base carries every commit, the safe path removes it:
        // the fixture's main has no work of its own, so moving it to
        // the branch tip is a fast-forward merge.
        try await git.checkout(worktreePath: world.repository.path, branch: base)
        try await git.resetHard(worktreePath: world.repository.path, ref: item.worktree.branch)
        overview = await world.service.overview()
        item = try #require(overview.groups.first?.items.first { $0.worktree.branch.hasPrefix("anchor_work") })
        #expect(try await world.service.cleanUpMergedWorktree(item: item, baseRef: base) == nil)
        #expect(FileManager.default.fileExists(atPath: item.worktree.path) == false)
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
        await world.service.closeSession(sessionName: sessionName, worktree: worktree)

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
        await world.service.closeSession(sessionName: sessionName, worktree: worktree)

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
    func `concurrent file listings share one ripgrep run`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let runner = SlowCountingRunner(standardOutput: "one.swift\ntwo.swift\n")
        let service = SessionService(
            paths: world.paths,
            git: GitClient(runner: runner),
            herdr: world.herdr,
            github: GitHubClient(runner: runner),
            transcripts: TranscriptReader(),
            spool: EventSpool(directory: world.paths.eventsDirectory),
            store: MetadataStore(file: world.paths.metadataFile),
            runners: [],
            processes: runner,
        )

        async let first = service.listFiles(worktreePath: world.repository.path)
        async let second = service.listFiles(worktreePath: world.repository.path)
        let listings = await [first, second]
        #expect(listings[0] == ["one.swift", "two.swift"])
        #expect(listings[1] == listings[0])
        #expect(runner.runCount == 1)

        // A listing after the shared one finished reads afresh.
        _ = await service.listFiles(worktreePath: world.repository.path)
        #expect(runner.runCount == 2)
    }
}

// MARK: - SlowCountingRunner

/// Answers fixed output slowly enough that concurrent callers
/// overlap, counting how many commands actually ran.
private final class SlowCountingRunner: ProcessRunner, Sendable {
    // MARK: Lifecycle

    init(standardOutput: String) {
        self.standardOutput = standardOutput
    }

    deinit {
        // Nothing to clean up.
    }

    // MARK: Internal

    var runCount: Int {
        count.withLock { $0 }
    }

    func run(
        _: [String],
        workingDirectory _: String?,
        environment _: [String: String],
    ) async throws -> ProcessResult {
        count.withLock { $0 += 1 }
        try await Task.sleep(for: .milliseconds(200))
        return ProcessResult(status: 0, standardOutput: standardOutput, standardError: "")
    }

    // MARK: Private

    private let count = Mutex(0)
    private let standardOutput: String
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
    func `a worktree named with an underscore keeps its conversations resumable in place`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }

        // Claude Code encodes the working directory by turning `/`,
        // `.` and `_` into dashes, so `install_method` lands in a
        // directory named `install-method`. Its conversation must
        // still be attributed to the real worktree path, the one
        // that exists, or Resume here has nothing to resume into.
        let worktreePath = try await world.service.createWorktreePath(
            repository: world.repository,
            branch: "install_method",
        )
        // Encoded as the CLI itself encodes, through the one rule the
        // service's runner shares; a hand-rolled copy here drifted
        // from it over the dots in the scratch path.
        let encoded = try #require(PromptCaptureRunner().transcriptDirectory(
            workingDirectory: worktreePath,
            sandboxHome: world.paths.sandboxHome,
        ))
        #expect(encoded.hasSuffix("-install-method"))
        try FileManager.default.createDirectory(atPath: encoded, withIntermediateDirectories: true)
        let transcript = #"{"type":"user","message":{"content":[{"type":"text","text":"underscored"}]}}"# + "\n"
        try transcript.write(toFile: encoded + "/underscored.jsonl", atomically: true, encoding: .utf8)

        let sessions = await world.service.repositorySessions(for: world.repository)
        let found = try #require(sessions.first { $0.session.id == "underscored" })
        #expect(found.worktreePath == worktreePath)
        #expect(FileManager.default.fileExists(atPath: found.worktreePath))
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
