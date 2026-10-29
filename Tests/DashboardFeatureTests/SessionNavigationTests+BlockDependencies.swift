import AgentIDEData
import AgentIDEDomain
@testable import DashboardFeature
import Foundation
import Testing

extension SessionNavigationTests {
    @Test(arguments: ["open", "merged", "old", "removed"])
    func `worktree dependencies wait for their current work to end`(outcome: String) async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let item = try #require(fixture.model.groups.first?.items.first)
        let other = WorktreeItem(
            worktree: Worktree(
                repositoryName: "repo",
                repositoryPath: fixture.repository.path,
                branch: "dependency",
                path: fixture.root + "/dependency",
            ),
            session: nil,
            isDirty: false,
            aheadOfUpstream: nil,
            hasUnread: false,
        )
        fixture.model.groups = [RepositoryGroup(repository: fixture.repository, items: [item, other])]
        try FileManager.default.createDirectory(atPath: other.worktree.path, withIntermediateDirectories: true)
        let block = WorkBlock(
            target: SidebarTarget(item.worktree),
            scope: .worktree,
            dependency: .worktree(SidebarTarget(other.worktree)),
        )
        #expect(fixture.model.editBlocks(block, targets: [block.target], replacing: []) == nil)
        let createdAt = try #require(fixture.model.block(for: item)).createdAt
        let summary = PullRequestSummary(
            number: 12,
            title: "Dependency",
            url: "",
            headBranch: "dependency",
            mergeable: "",
            reviewDecision: "",
            checks: "",
            state: outcome == "open" ? "OPEN" : "MERGED",
            closedAt: createdAt.addingTimeInterval(outcome == "old" ? -1 : 1),
        )
        fixture.model.pullRequests.rememberListing(
            repositoryPath: fixture.repository.path, scope: .branch("dependency"), summaries: [summary],
        )
        if outcome == "removed" {
            try FileManager.default.removeItem(atPath: other.worktree.path)
        }
        await fixture.model.refreshWorkBlocks(force: true)
        #expect((fixture.model.block(for: item) == nil) == ["merged", "removed"].contains(outcome))
    }
}
