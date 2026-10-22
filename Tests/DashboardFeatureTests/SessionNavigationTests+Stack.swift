import AgentIDEDomain
@testable import DashboardFeature
import Testing

extension SessionNavigationTests {
    @Test(arguments: [false, true])
    func `the sidebar uses GitHub positions and includes unpublished branches`(unpublished: Bool) throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let item = try #require(fixture.model.groups.first?.items.first)
        if unpublished {
            fixture.model.derivedStacks[item.worktree.path] = BranchStack(
                base: "trunk", branches: ["bottom", "middle", "main", "upper", "unpushed"], checkedOut: "main",
            )
        }
        fixture.model.store.update { metadata in
            metadata.pullRequestCache[fixture.repository.path + "#main"] = PullRequestSummary(
                number: 7,
                title: "Work",
                url: "",
                headBranch: "main",
                mergeable: "",
                reviewDecision: "",
                checks: "",
                baseBranch: "middle",
                stackStanding: StackStanding(position: 3, height: 4, base: "middle"),
            )
        }
        #expect(fixture.model.stackStanding(for: item)
            == StackStanding(position: 3, height: unpublished ? 5 : 4, base: "middle"))
    }
}
