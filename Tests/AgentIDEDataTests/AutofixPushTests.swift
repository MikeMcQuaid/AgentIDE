import AgentIDEData
import Foundation
import Testing

struct AutofixPushTests {
    @Test
    func `a pinned push sends only the reported commit and refuses a moved remote`() async throws {
        let root = try TestSupport.temporaryDirectory("autofix-push")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let repository = root + "/repo"
        let fork = root + "/fork.git"
        try await TestSupport.makeRepository(at: repository)
        try await TestSupport.runGit(["clone", "--bare", repository, fork], in: root)
        try await TestSupport.runGit(["checkout", "-b", "feature"], in: repository)
        try await TestSupport.runGit(["remote", "add", "fork", fork], in: repository)
        try await TestSupport.runGit(["push", "--set-upstream", "fork", "feature"], in: repository)
        let git = GitClient(runner: FoundationProcessRunner())
        let original = try #require(await git.tip(of: "HEAD", worktreePath: repository))
        try await TestSupport.runGit(["commit", "--allow-empty", "-m", "Fix"], in: repository)
        let fix = try #require(await git.tip(of: "HEAD", worktreePath: repository))
        try await TestSupport.runGit(["commit", "--allow-empty", "-m", "Later work"], in: repository)
        try await git.push(
            worktreePath: repository, branch: "feature", remote: fork, expectedTip: original, sourceCommit: fix,
        )
        #expect(await git.tip(of: "feature", worktreePath: fork) == fix)
        #expect(await git.branchRemote(worktreePath: repository, branch: "feature") == "fork")
        await #expect(throws: (any Error).self) {
            try await git.push(
                worktreePath: repository, branch: "feature", remote: fork, expectedTip: original, sourceCommit: "HEAD",
            )
        }
        #expect(await git.tip(of: "feature", worktreePath: fork) == fix)
        try await TestSupport.runGit(["config", "remote.fork.pushurl", "https://github.com/other/repo"], in: repository)
        #expect(await git.remoteURL(named: "fork", worktreePath: repository, forPush: true)
            == "https://github.com/other/repo")
    }
}
