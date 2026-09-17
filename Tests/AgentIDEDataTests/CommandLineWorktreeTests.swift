@testable import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

struct CommandLineWorktreeTests {
    // MARK: Internal

    @Test(arguments: [nil, -3_601, -1_800] as [TimeInterval?])
    func `the command refreshes old fetches and branches from origin`(fetchAge: TimeInterval?) async throws {
        let root = try TestSupport.temporaryDirectory("command-worktree")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let origin = root + "/origin"
        let repository = root + "/repo"
        try await TestSupport.makeRepository(at: origin)
        try await TestSupport.runGit(["branch", "--move", "main", "trunk"], in: origin)
        try await TestSupport.runGit(["clone", origin, repository], in: root)
        try await TestSupport.runGit(["fetch", "origin"], in: repository)
        let git = GitClient(runner: FoundationProcessRunner())
        let cached = await git.commitHash(of: "origin/HEAD", worktreePath: repository)
        try await TestSupport.runGit(["commit", "--allow-empty", "-m", "Upstream change"], in: origin)
        let latest = await git.commitHash(of: "HEAD", worktreePath: origin)
        try await TestSupport.runGit(["checkout", "--detach", "HEAD"], in: repository)
        if let fetchAge {
            try FileManager.default.setAttributes(
                [.modificationDate: Date().addingTimeInterval(fetchAge)],
                ofItemAtPath: repository + "/.git/FETCH_HEAD",
            )
        } else {
            try FileManager.default.removeItem(atPath: repository + "/.git/FETCH_HEAD")
        }

        let result = try await Self.createWorktree(in: repository, at: root + "/worktree")

        #expect(result.succeeded)
        let shouldFetch = fetchAge == nil || (fetchAge ?? 0) < -3_600
        #expect(await git.commitHash(of: "HEAD", worktreePath: root + "/worktree") == (shouldFetch ? latest : cached))
        #expect(result.standardError.contains("Fetching") == shouldFetch)
        let upstream = try await TestSupport.runGit(
            ["for-each-ref", "--format=%(upstream)", "refs/heads/new-session"],
            in: repository,
        )
        #expect(upstream.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test
    func `a failed command fetch is retried before creating a worktree`() async throws {
        let root = try TestSupport.temporaryDirectory("command-fetch-failure")
        defer { try? FileManager.default.removeItem(atPath: root) }
        try await TestSupport.makeRepository(at: root + "/repo")
        try await TestSupport.runGit(["remote", "add", "origin", root + "/missing"], in: root + "/repo")

        for _ in 0 ..< 2 {
            let result = try await Self.createWorktree(in: root + "/repo", at: root + "/worktree")
            #expect(result.succeeded == false)
            #expect(result.standardError.contains("Fetching"))
            #expect(FileManager.default.fileExists(atPath: root + "/worktree") == false)
        }
    }

    @Test
    func `the command follows a default branch that origin renamed`() async throws {
        let root = try TestSupport.temporaryDirectory("command-renamed")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let origin = root + "/origin"
        let repository = root + "/repo"
        try await TestSupport.makeRepository(at: origin)
        try await TestSupport.runGit(["branch", "--move", "main", "trunk"], in: origin)
        try await TestSupport.runGit(["clone", "-q", origin, repository], in: root)
        // Renamed on origin after the clone: origin/HEAD here still
        // says trunk, which the pruning fetch (a clone leaves no
        // FETCH_HEAD, so the command fetches) then removes.
        try await TestSupport.runGit(["branch", "--move", "trunk", "main"], in: origin)
        let git = GitClient(runner: FoundationProcessRunner())
        let tip = await git.commitHash(of: "main", worktreePath: origin)

        let result = try await Self.createWorktree(in: repository, at: root + "/worktree")

        #expect(result.succeeded)
        #expect(result.standardError.contains("Following origin's default branch"))
        #expect(await git.commitHash(of: "HEAD", worktreePath: root + "/worktree") == tip)
        #expect(await git.defaultBaseRef(of: Repository(name: "repo", path: repository)) == "origin/main")
    }

    @Test(arguments: ["main", "master", "local-work"])
    func `repositories without origin still create worktrees`(branch: String) async throws {
        let root = try TestSupport.temporaryDirectory("command-local")
        defer { try? FileManager.default.removeItem(atPath: root) }
        try await TestSupport.makeRepository(at: root + "/repo")
        if branch != "main" {
            try await TestSupport.runGit(["branch", "--move", "main", branch], in: root + "/repo")
        }

        let result = try await Self.createWorktree(in: root + "/repo", at: root + "/worktree")

        #expect(result.succeeded)
        #expect(FileManager.default.fileExists(atPath: root + "/worktree/README.md"))
    }

    // MARK: Private

    private static func createWorktree(in repository: String, at worktree: String) async throws -> ProcessResult {
        let command = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "bin/agentide")
        let functions = try String(contentsOf: command, encoding: .utf8)
            .components(separatedBy: "\nif [ \"${1:-}\" = \"new\" ]; then")[0]
        return try await FoundationProcessRunner().run(
            [
                "/bin/sh", "-c", functions + "\ncreate_worktree " + repository.shellQuoted
                    + " new-session " + worktree.shellQuoted,
            ],
            workingDirectory: nil,
            environment: [:],
        )
    }
}
