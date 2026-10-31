import Foundation
@testable import SanductorData
import SanductorDomain
import Testing

// MARK: - AutofixConflictIntegrationTests

struct AutofixConflictIntegrationTests {
    // MARK: Internal

    @Test
    func `conflict detection fetches in the worktree without changing its index or files`() async throws {
        let (world, target) = try await Self.makeConflict()
        defer { world.tearDown() }
        let path = target.worktree.path
        let runner = ConflictFetchRunner()
        let git = GitClient(runner: runner) { true }
        let service = world.service(herdr: world.herdr, git: git)
        let original = try #require(await git.commitHash(of: "HEAD", worktreePath: path))
        let base = try #require(try await service.autofixConflictBase(target: target, summary: Self.summary))
        #expect(await base == git.commitHash(of: "HEAD", worktreePath: world.root + "/origin"))
        #expect(await runner.directories == [path])
        #expect(await git.commitHash(of: "HEAD", worktreePath: path) == original)
        #expect(await git.isDirty(worktreePath: path) == false)
        #expect(try String(contentsOfFile: path + "/README.md", encoding: .utf8) == "feature\n")
    }

    @Test
    func `conflict detection cannot execute a repository configured merge driver`() async throws {
        let (world, target) = try await Self.makeConflict()
        defer { world.tearDown() }
        let path = target.worktree.path
        let marker = world.root + "/merge-driver-ran"
        try "README.md merge=untrusted\n".write(toFile: path + "/.gitattributes", atomically: true, encoding: .utf8)
        try await world.service.git.commitAll(worktreePath: path, message: "Configure merge driver")
        try await TestSupport.runGit(
            ["config", "merge.untrusted.driver", "touch " + marker.shellQuoted + "; false"], in: path,
        )
        #expect(try await world.service.autofixConflictBase(target: target, summary: Self.summary) != nil)
        #expect(FileManager.default.fileExists(atPath: marker) == false)
    }

    @Test
    func `an unavailable fetched target is an error rather than a completed rebase`() async throws {
        let (world, target) = try await Self.makeConflict()
        defer { world.tearDown() }
        try await TestSupport.runGit(["branch", "--move", "release/next", "renamed"], in: world.root + "/origin")
        await #expect(throws: SessionServiceError.self) {
            try await world.service.autofixConflictBase(target: target, summary: Self.summary)
        }
        #expect(await world.service.git.currentBranch(worktreePath: target.worktree.path) == "feature")
        #expect(await world.service.git.isDirty(worktreePath: target.worktree.path) == false)
    }

    @Test
    func `a local rebase clears stale remote conflicts without another fetch`() async throws {
        let (world, target) = try await Self.makeConflict()
        defer { world.tearDown() }
        let path = target.worktree.path
        let runner = ConflictFetchRunner()
        let git = GitClient(runner: runner) { true }
        let service = world.service(herdr: world.herdr, git: git)
        let base = try #require(try await service.autofixConflictBase(target: target, summary: Self.summary))
        let conflicted = try await git.git(["rebase", "origin/release/next", "feature"], in: path, allowFailure: true)
        #expect(conflicted.status == 1)
        try "feature and upstream\n".write(toFile: path + "/README.md", atomically: true, encoding: .utf8)
        try await TestSupport.runGit(["add", "README.md"], in: path)
        try await git.git(
            ["-c", "commit.gpgsign=false", "rebase", "--continue"], in: path, environment: ["GIT_EDITOR": "true"],
        )
        #expect(try await service.autofixConflictBase(target: target, summary: Self.summary) == nil)
        #expect(await git.isAncestor(base, of: "HEAD", worktreePath: path))
        #expect(await runner.directories == [path])
    }

    // MARK: Private

    private static let summary: PullRequestSummary = .init(
        number: 1,
        title: "PR",
        url: "pr",
        headBranch: "feature",
        mergeable: "CONFLICTING",
        reviewDecision: "",
        checks: "",
        baseBranch: "release/next",
    )

    private static func makeConflict() async throws -> (World, AutofixDriver.Target) {
        let world = try await World.make()
        let origin = world.root + "/origin"
        try await TestSupport.runGit(["clone", world.repository.path, origin], in: world.root)
        try await TestSupport.runGit(["branch", "--move", "main", "release/next"], in: origin)
        try await TestSupport.runGit(["remote", "add", "origin", origin], in: world.repository.path)
        let path = world.root + "/worktree"
        try await TestSupport.runGit(["worktree", "add", "-b", "feature", path, "main"], in: world.repository.path)
        try "feature\n".write(toFile: path + "/README.md", atomically: true, encoding: .utf8)
        try await world.service.git.commitAll(worktreePath: path, message: "Feature change")
        try "upstream\n".write(toFile: origin + "/README.md", atomically: true, encoding: .utf8)
        try await TestSupport.runGit([
            "-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-am", "Upstream change",
        ], in: origin)
        return (world, AutofixDriver.Target(
            worktree: Worktree(
                repositoryName: "repo", repositoryPath: world.repository.path, branch: "feature", path: path,
            ),
            session: AgentSession(name: "agent", agent: .codexCLI, status: .running, paneID: "pane", activity: .idle),
        ))
    }
}

// MARK: - ConflictFetchRunner

private actor ConflictFetchRunner: ProcessRunner {
    var directories: [String] = []

    func run(
        _ arguments: [String], workingDirectory: String?, environment: [String: String], outputLimit: Int?,
    ) async throws -> ProcessResult {
        if arguments.contains("fetch"), let workingDirectory {
            directories.append(workingDirectory)
        }
        return try await FoundationProcessRunner().run(
            arguments, workingDirectory: workingDirectory, environment: environment, outputLimit: outputLimit,
        )
    }
}
