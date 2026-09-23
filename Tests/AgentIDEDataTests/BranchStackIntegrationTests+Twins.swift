import AgentIDEData
import AgentIDEDomain
import Testing

extension BranchStackIntegrationTests {
    @Test(arguments: ["origin", "contributor"])
    func `a local-only twin of a pushed branch never hides it, even checked out`(remote: String) async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let repository = try #require(world.service.repositories().first)
        try await Self.commit("first", in: repository.path)
        for branch in ["lower", "upper"] {
            _ = try await TestSupport.runGit(["checkout", "-b", branch], in: repository.path)
            try await Self.commit(branch + " work", in: repository.path)
            try await TestSupport.runGit(["config", "branch." + branch + ".pushremote", remote], in: repository.path)
            _ = try await TestSupport.runGit(
                ["update-ref", "refs/remotes/" + remote + "/" + branch, branch],
                in: repository.path,
            )
        }
        // The worktree's own name, cut at the same commit as the
        // pushed branch above and checked out: the shape a worktree
        // takes when its branch was renamed after being pushed.
        _ = try await TestSupport.runGit(["checkout", "-b", "worktree-name", "upper"], in: repository.path)
        let worktree = Worktree(
            repositoryName: repository.name,
            repositoryPath: repository.path,
            branch: "worktree-name",
            path: repository.path,
        )

        let stack = await world.service.stack(for: worktree)

        // The pushed name stands for the pair: it is the one a pull
        // request can be open on, and listing the local-only twin
        // instead put that pull request out of reach entirely.
        #expect(stack.branches == ["lower", "upper"])
        // And it stands in for what is checked out, so the actions
        // that move the checked-out branch stay live.
        #expect(stack.checkedOut == "upper")
        #expect(await world.service.stackFacts(for: worktree).unpushed.isEmpty)
    }
}
