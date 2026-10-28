@testable import SanductorData
import SanductorDomain
import Testing

struct ReviewBaseTests {
    @Test
    func `review bases follow a checkout with a retained worktree record`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let worktree = Worktree(
            repositoryName: world.repository.name,
            repositoryPath: world.repository.path,
            branch: "main",
            path: world.repository.path,
        )
        for (number, branch, base) in [(1, "main", "old-base"), (2, "feature", "new-base")] {
            world.service.pullRequestReads.rememberListing(
                repositoryPath: world.repository.path,
                scope: .branch(branch),
                summaries: [
                    PullRequestSummary(
                        number: number,
                        title: "Work",
                        url: "",
                        headBranch: branch,
                        mergeable: "",
                        reviewDecision: "",
                        checks: "",
                        baseBranch: base,
                        state: "OPEN",
                    ),
                ],
            )
        }
        #expect(await world.service.reviewBase(for: worktree) == "origin/old-base")

        try await TestSupport.runGit(["checkout", "-b", "feature"], in: world.repository.path)

        #expect(await world.service.reviewBase(for: worktree) == "origin/new-base")
    }
}
