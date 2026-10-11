import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

struct LocalReviewIdentityTests {
    @Test(arguments: ["matching", "changed code", "changed branch", "different fork"])
    func `legacy PR association requires matching code branch and fork`(change: String) async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let path = world.repository.path
        try await TestSupport.runGit(["checkout", "-b", "feature"], in: path)
        try await TestSupport.runGit(["remote", "add", "origin", "git@github.com:owner/repo.git"], in: path)
        let review = try await LocalReview(
            reviewer: .codexCLI,
            snapshot: "s",
            revision: world.service.localReviewRevision(worktreePath: path),
            threads: [],
        )
        world.service.saveLocalReview(review, worktreePath: path)
        if change == "changed code" {
            try "new content".write(toFile: path + "/new.swift", atomically: true, encoding: .utf8)
        } else if change == "changed branch" {
            try await TestSupport.runGit(["checkout", "-b", "other"], in: path)
        }
        let summary = PullRequestSummary(
            number: 7,
            title: "Review",
            url: "https://github.com/owner/repo/pull/7",
            headBranch: "feature",
            mergeable: "",
            reviewDecision: "",
            checks: "",
            headRepository: change == "different fork" ? "another/repo" : "owner/repo",
        )
        let restored = await world.service.restoreLocalReviewIdentity(
            worktreePath: path, repositoryPath: path, summary: summary,
        )
        #expect(restored == (change == "matching"))
        let saved = try #require(world.service.localReview(worktreePath: path))
        #expect(saved.branch == (restored ? "feature" : nil))
        #expect(saved.pullRequestURL == (restored ? summary.url : nil))
        #expect(saved.runID == review.runID)
        #expect(await world.service.restoreLocalReviewIdentity(
            worktreePath: path, repositoryPath: path, summary: summary,
        ) == false)
        let store = MetadataStore(file: world.paths.metadataFile + ".restart")
        try FileManager.default.copyItem(
            atPath: world.paths.metadataFile, toPath: world.paths.metadataFile + ".restart",
        )
        #expect(store.load().localReviews[path] == saved)
    }
}
