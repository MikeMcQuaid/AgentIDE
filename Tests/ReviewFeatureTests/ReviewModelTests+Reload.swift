import AgentIDEData
import Foundation
@testable import ReviewFeature
import Testing

extension ReviewModelTests {
    @Test
    func `opening a short commit reference preserves the draft on return`() async throws {
        let path = FileManager.default.currentDirectoryPath + "/.test-scratch/review-link-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: path) }
        try await makeRepository(at: path)
        let git = GitClient(runner: FoundationProcessRunner())
        let first = try #require(await git.commitHash(of: "HEAD", worktreePath: path))
        try "new\n".write(toFile: path + "/new.txt", atomically: true, encoding: .utf8)
        try await runGit(["add", "new.txt"], in: path)
        try await runGit(["commit", "-m", "Later commit"], in: path)
        let head = await git.commitHash(of: "HEAD", worktreePath: path)
        let model = ReviewModel(worktreePath: path, repositoryName: path, git: git)
        model.scope = .lastCommit
        await model.reload()
        model.commitMessage = "My unfinished draft"
        await model.showCommit("0000000000000000000000000000000000000000")
        #expect(model.commitTarget == nil)
        #expect(model.commitMessage == "My unfinished draft")
        #expect(model.status?.contains("not available") == true)
        let shortHashLength = 5
        await model.showCommit(String(first.prefix(shortHashLength)))
        #expect(model.status == nil)
        #expect(model.commitTarget == first)
        #expect(model.commitMessage == "Initial commit")
        #expect(model.files.contains { $0.path == "new.txt" } == false)
        #expect(model.isReadOnly)
        #expect(await git.commitHash(of: "HEAD", worktreePath: path) == head)
        await model.showCommit(nil)
        #expect(model.commitMessage == "My unfinished draft")
        #expect(model.originalMessage == "Later commit")
        #expect(model.messageEdited)
        #expect(model.files.map(\.path) == ["new.txt"])
    }

    @Test(arguments: [ReviewModel.Scope.branch, .lastCommit], [false, true])
    func `refreshing branch state preserves an edited commit message`(
        scope: ReviewModel.Scope, checkout: Bool,
    ) async throws {
        let path = FileManager.default.currentDirectoryPath + "/.test-scratch/review-message-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: path) }
        try await makeRepository(at: path)
        let model = ReviewModel(
            worktreePath: path, repositoryName: path, git: GitClient(runner: FoundationProcessRunner()),
        )
        model.scope = scope
        await model.reload()
        model.commitMessage = "Keep my edited message"

        if checkout {
            try await runGit(["checkout", "-b", "feature"], in: path)
            try await runGit(["commit", "--allow-empty", "-m", "New branch message"], in: path)
        }

        await model.reload()

        #expect(model.commitMessage == "Keep my edited message")
        #expect(model.messageEdited)
        #expect(model.originalMessage == (checkout ? "New branch message" : "Initial commit"))
    }

    @Test(arguments: [
        ("lastCommit", "--patch"), ("uncommitted", "diff"), ("upstream", "diff"),
        ("branch", "diff"), ("commit", "--patch"), ("stack", "diff"),
        ("lastCommit", "--format=%B"), ("branch", "--format=%h %s%d"), ("stack", "--format=commit %H%n%B"),
        ("lastCommit", "--is-inside-work-tree"), ("upstream", "refs/remotes/origin/feature"),
    ], [false, true])
    func `a superseded reload cannot replace the selected diff or availability`(
        scenario: (String, String), fails: Bool,
    ) async throws {
        let (target, pause) = scenario
        let path = FileManager.default.currentDirectoryPath + "/.test-scratch/review-reload-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: path) }
        try await makeRepository(at: path)
        try await runGit(["checkout", "-b", "feature"], in: path)
        try "old\n".write(toFile: path + "/old.txt", atomically: true, encoding: .utf8)
        try await runGit(["add", "-A"], in: path)
        try await runGit(["commit", "-m", "Old message"], in: path)
        try await runGit(["update-ref", "refs/remotes/origin/feature", "HEAD^"], in: path)
        try "stale\n".write(toFile: path + "/stale.txt", atomically: true, encoding: .utf8)
        let runner = PausedDiffRunner(pause: pause, fails: fails)
        let model = ReviewModel(
            worktreePath: path, repositoryName: path, git: GitClient(runner: runner),
        ) { "main" }
        model.scope = ReviewModel.Scope(storageName: target) ?? .branch
        model.commitTarget = target == "commit" ? "HEAD" : nil
        model.stackTarget = target == "stack" ? (parent: "main", branch: "feature") : nil
        model.worktreeExists = { _ in pause == "--is-inside-work-tree" }
        var arrivals = runner.started.stream.makeAsyncIterator()
        let earlier = Task {
            await model.reload()
        }
        _ = await arrivals.next()
        try FileManager.default.removeItem(atPath: path + "/stale.txt")
        try "current\n".write(toFile: path + "/current.txt", atomically: true, encoding: .utf8)
        model.scope = .uncommitted
        model.commitTarget = nil
        model.stackTarget = nil
        await model.reload()
        #expect(model.files.map(\.path) == ["current.txt"])
        let message = model.commitMessage
        let commits = model.branchCommits
        let head = model.lastCommitHash

        await runner.resume()
        await earlier.value

        #expect(model.files.map(\.path) == ["current.txt"])
        #expect(model.showsUncommitted)
        #expect(model.localReviewContext.isEmpty)
        #expect(model.commitMessage == message)
        #expect(model.branchCommits == commits)
        #expect(model.lastCommitHash == head)
        #expect(model.isRepositoryAvailable)
        #expect(model.hasLoaded)
    }
}

// MARK: - PausedDiffRunner

private actor PausedDiffRunner: ProcessRunner {
    // MARK: Lifecycle

    init(pause: String, fails: Bool) {
        self.pause = pause
        self.fails = fails
    }

    // MARK: Internal

    let started: (stream: AsyncStream<Void>, continuation: AsyncStream<Void>.Continuation) = AsyncStream.makeStream()

    func run(
        _ arguments: [String], workingDirectory: String?, environment: [String: String], outputLimit: Int?,
    ) async throws -> ProcessResult {
        if pause == "--is-inside-work-tree", hasPaused == false, arguments.contains("--patch") {
            throw CocoaError(.fileNoSuchFile)
        }
        let pauses = hasPaused == false && arguments.contains(pause)
        if pauses {
            hasPaused = true
        }
        let result = try await FoundationProcessRunner().run(
            arguments, workingDirectory: workingDirectory, environment: environment, outputLimit: outputLimit,
        )
        if pauses {
            await withCheckedContinuation { continuation in
                pending = continuation
                started.continuation.yield(())
            }
            if pause == "--is-inside-work-tree" {
                return ProcessResult(status: 0, standardOutput: "false", standardError: "")
            }
            if fails {
                throw CocoaError(.fileNoSuchFile)
            }
        }
        return result
    }

    func resume() {
        pending?.resume()
        pending = nil
    }

    // MARK: Private

    private let pause: String
    private let fails: Bool
    private var hasPaused = false
    private var pending: CheckedContinuation<Void, Never>?
}
