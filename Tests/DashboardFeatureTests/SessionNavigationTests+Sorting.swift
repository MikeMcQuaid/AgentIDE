@testable import DashboardFeature
import Foundation
import SanductorData
import SanductorDomain
import Testing

extension SessionNavigationTests {
    @Test(arguments: ["main", "trunk"])
    func `idle checkouts and linked worktrees group separately with blocks above the default branch`(
        defaultBranch: String,
    ) throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let checkout = try #require(fixture.model.groups.first?.items.first).renamed(branch: defaultBranch)
        let worktree = Fixture.item(defaultBranch, repository: fixture.repository)
        let blocked = Fixture.item("blocked", repository: fixture.repository)
        fixture.model.groups = [
            RepositoryGroup(
                repository: fixture.repository, items: [checkout, worktree, blocked], defaultBranch: defaultBranch,
            ),
        ]
        #expect(fixture.model.editBlocks(
            WorkBlock(target: SidebarTarget(blocked.worktree), scope: .worktree, dependency: .note("Wait")),
            targets: [SidebarTarget(blocked.worktree)],
            replacing: [],
        ) == nil)
        #expect(fixture.model.sidebarStatus(for: checkout).rawValue == "Default branch")
        #expect(fixture.model.sidebarStatus(for: worktree).rawValue == "Worktree")
        #expect(fixture.model.statusGroups.map(\.status.rawValue) == ["Worktree", "Blocked", "Default branch"])
        fixture.model.groups[0].items[0] = checkout.renamed(branch: "feature")
        #expect(fixture.model.statusGroups.map(\.status.rawValue) == ["Worktree", "Branch", "Blocked"])
        fixture.model.groups = [RepositoryGroup(repository: fixture.repository, items: [checkout])]
        #expect(fixture.model.sidebarStatus(for: checkout).rawValue == "Branch")
    }

    @Test
    func `repository sorting follows visible status without changing its rows`() throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let first = try #require(fixture.model.groups.first?.items.first)
        let second = WorktreeItem(
            worktree: Worktree(repositoryName: "another", repositoryPath: "/another", branch: "main", path: "/another"),
            session: AgentSession(name: "agent", agent: .codexCLI, status: .running, activity: .working),
            isDirty: false,
            aheadOfUpstream: nil,
        )
        fixture.model.groups = [
            RepositoryGroup(repository: fixture.repository, items: [first]),
            RepositoryGroup(
                repository: Repository(name: "another", path: "/another", fullName: "z/another"),
                items: [second],
            ),
        ]
        #expect(fixture.model.repositoryGroups(sortedBy: .activity) == fixture.model.groups)
        fixture.model.select(first)
        #expect(fixture.model.repositoryGroups(sortedBy: .status).map(\.repository.name) == ["another", "repo"])
        #expect(fixture.model.repositoryGroups(sortedBy: .name).map(\.repository.name) == ["repo", "another"])
        let block = WorkBlock(target: SidebarTarget(second.worktree), scope: .worktree, dependency: .note("Wait"))
        #expect(fixture.model.editBlocks(block, targets: [block.target], replacing: []) == nil)
        #expect(fixture.model.repositoryGroups(sortedBy: .status).map(\.repository.name) == ["repo", "another"])
        #expect(fixture.model.groups.flatMap(\.items) == [first, second])
        #expect(fixture.model.selection?.id == first.id)
    }
}
