@testable import AgentIDEData
import Foundation
import Testing

struct GitFetchIntegrationTests {
    @Test(arguments: [false, true], ["remote", "pushremote"])
    func `fetch updates active forks and skips unused remotes`(linked: Bool, remoteKey: String) async throws {
        let root = try TestSupport.temporaryDirectory("fetch-remotes")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let origin = root + "/origin"
        let fork = root + "/fork"
        let path = root + "/repo"
        try await TestSupport.makeRepository(at: origin)
        try await TestSupport.makeRepository(at: fork)
        try await TestSupport.runGit(["clone", "-q", origin, path], in: root)
        try await TestSupport.runGit(["remote", "add", "contributor", fork], in: path)
        try await TestSupport.runGit(["remote", "add", "unused-fork", root + "/missing"], in: path)
        try await TestSupport.runGit(["branch", "obsolete"], in: origin)
        try await TestSupport.runGit(["fetch", "origin"], in: path)
        try await TestSupport.runGit(["branch", "--delete", "obsolete"], in: origin)
        try await TestSupport.runGit(["commit", "--allow-empty", "-m", "Origin moved"], in: origin)
        try await TestSupport.runGit(["commit", "--allow-empty", "-m", "Fork moved"], in: fork)
        if linked {
            try await TestSupport.runGit(["worktree", "add", "-b", "topic", root + "/worktree"], in: path)
        } else {
            try await TestSupport.runGit(["checkout", "-b", "topic"], in: path)
        }
        try await TestSupport.runGit(["config", "branch.topic." + remoteKey, "contributor"], in: path)
        try await TestSupport.runGit(["config", "branch.topic.merge", "refs/heads/main"], in: path)
        let git = GitClient(runner: FoundationProcessRunner())

        try await git.fetch(repositoryPath: path)

        #expect(await git.commitHash(of: "origin/main", worktreePath: path)
            == git.commitHash(of: "HEAD", worktreePath: origin))
        #expect(await git.commitHash(of: "contributor/main", worktreePath: path)
            == git.commitHash(of: "HEAD", worktreePath: fork))
        #expect(await git.refExists(worktreePath: path, ref: "refs/remotes/origin/obsolete") == false)
        #expect(await git.remoteURL(named: "unused-fork", worktreePath: path) == root + "/missing")

        try await TestSupport.runGit(["remote", "set-url", "contributor", root + "/missing"], in: path)
        await #expect(throws: CommandError.self) {
            try await git.fetch(repositoryPath: path)
        }

        if linked {
            try await TestSupport.runGit(["worktree", "remove", root + "/worktree"], in: path)
        } else {
            try await TestSupport.runGit(["checkout", "main"], in: path)
        }
        try await git.fetch(repositoryPath: path)
    }
}
