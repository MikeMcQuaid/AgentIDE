@testable import AgentIDEData
import Foundation
import Testing

// MARK: - SigningWarmupTests

struct SigningWarmupTests {
    @Test
    func `a rejected signing warm-up still starts the feedback loop`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let path = world.root + "/feature"
        try await TestSupport.runGit(["worktree", "add", "-b", "feature", path, "main"], in: world.repository.path)
        try await BranchStackIntegrationTests.signable(path)
        try await TestSupport.runGit(["config", "gpg.ssh.program", "/usr/bin/false"], in: path)
        var state = world.service.feedbackState(repositoryPath: world.repository.path, worktreePath: path, summary: nil)
        state.autofixLocalReviews = true
        try await world.service.startFeedbackLoop(state)
        let started = world.service.currentFeedback(state)
        #expect(started.isAutomatic)
        #expect(started.lastResult.contains("Signing warm-up failed"))
        #expect(started.lastResult.contains("still try signing"))
        #expect(started.roundsStarted == 0)
    }

    @Test(arguments: [true, false])
    func `signing warm-up leaves the branch and pending changes untouched`(fails: Bool) async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let path = world.repository.path
        try await BranchStackIntegrationTests.signable(path)
        if fails {
            try await TestSupport.runGit(["config", "gpg.ssh.program", "/usr/bin/false"], in: path)
        }
        try "staged".write(toFile: path + "/pending", atomically: true, encoding: .utf8)
        try await TestSupport.runGit(["add", "pending"], in: path)
        try "unstaged".write(toFile: path + "/pending", atomically: true, encoding: .utf8)
        let head = await world.service.git.tip(of: "HEAD", worktreePath: path)
        let index = try await TestSupport.runGit(["write-tree"], in: path).standardOutput
        let runner = SigningWarmupRunner()
        let git = GitClient(runner: runner)
        if fails {
            await #expect(throws: (any Error).self) { try await git.warmSigning(worktreePath: path) }
        } else {
            try await git.warmSigning(worktreePath: path)
            let signed = try #require(await runner.signed)
            #expect(await git.allCommitsSigned(worktreePath: path, range: signed + "^!"))
            #expect(await git.commitHash(of: signed + "^{tree}", worktreePath: path)
                == git.commitHash(of: "HEAD^{tree}", worktreePath: path))
        }
        #expect(await runner.calls == 1)
        #expect(await git.tip(of: "HEAD", worktreePath: path) == head)
        #expect(try await TestSupport.runGit(["write-tree"], in: path).standardOutput == index)
        #expect(try String(contentsOfFile: path + "/pending", encoding: .utf8) == "unstaged")
    }
}

// MARK: - SigningWarmupRunner

private actor SigningWarmupRunner: ProcessRunner {
    var calls = 0
    var signed: String?

    func run(
        _ arguments: [String], workingDirectory: String?, environment: [String: String], outputLimit: Int?,
    ) async throws -> ProcessResult {
        if arguments.contains("commit-tree") {
            calls += 1
        }
        let result = try await FoundationProcessRunner().run(
            arguments, workingDirectory: workingDirectory, environment: environment, outputLimit: outputLimit,
        )
        if arguments.contains("commit-tree"), result.succeeded {
            signed = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }
}
