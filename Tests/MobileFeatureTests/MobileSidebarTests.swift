@testable import MobileFeature
import SanductorDomain
import Testing

struct MobileSidebarTests {
    @Test(arguments: [
        ("trunk", SidebarStatus.defaultBranch),
        ("feature", .branch),
        ("trunk", .worktree),
    ], [AgentKind?.none, .codexCLI])
    func `phone idle groups follow live branch switches and keep agents separate`(
        scenario: (String, SidebarStatus), agent: AgentKind?,
    ) {
        let path = scenario.1 == .worktree ? "/tree" : "/repo"
        let target = SidebarTarget(repository: "repo", repositoryPath: "/repo", branch: "old", path: path)
        let sidebar = [
            SidebarRepository(name: "repo-", owner: nil, worktrees: ["/other"]),
            SidebarRepository(
                name: "repo",
                owner: nil,
                worktrees: [path],
                entries: [SidebarEntry(target: target, status: .idleAgent, activity: .idle, block: nil)],
                defaultBranch: "trunk",
            ),
        ]
        let session = MobileSession(
            id: "pane",
            name: "session",
            repository: "repo",
            branch: scenario.0,
            agent: agent,
            activity: .idle,
            directory: path,
        )
        #expect(session.sidebarEntry(in: sidebar)?.status == (agent == nil ? scenario.1 : .idleAgent))
    }

    @Test(arguments: [AgentKind?.none, .codexCLI], [SidebarStatus.worktree, .idleAgent])
    func `idle phone panes use their own agent rather than another pane in the worktree`(
        agent: AgentKind?, projected: SidebarStatus,
    ) {
        let target = SidebarTarget(repository: "repo", repositoryPath: "/repo", branch: "work", path: "/tree")
        let sidebar = [
            SidebarRepository(name: "repo", owner: nil, worktrees: ["/tree"], entries: [
                SidebarEntry(target: target, status: projected, activity: .idle, block: nil),
            ]),
        ]
        let session = MobileSession(
            id: "pane",
            name: "session",
            repository: "repo",
            branch: "work",
            agent: agent,
            activity: .idle,
            directory: "/tree",
        )
        #expect(session.sidebarEntry(in: sidebar)?.status == (agent == nil ? .worktree : .idleAgent))
        #expect(session.sidebarStatus() == (agent == nil ? .branch : .idleAgent))
    }

    @Test
    func `a completed turn aged into idle on the Mac stays idle on the phone`() {
        let target = SidebarTarget(repository: "repo", repositoryPath: "/repo", branch: "work", path: "/tree")
        let sidebar = [
            SidebarRepository(name: "repo", owner: nil, worktrees: ["/tree"], entries: [
                SidebarEntry(target: target, status: .idleAgent, activity: .done, block: nil),
            ]),
        ]
        let session = MobileSession(
            id: "pane",
            name: "agent",
            repository: "repo",
            branch: "work",
            agent: .codexCLI,
            activity: .done,
            directory: "/tree",
        )
        #expect(session.sidebarStatus() == .done)
        #expect(session.sidebarEntry(in: sidebar)?.status == .idleAgent)
    }

    @Test(arguments: [WorkBlock.Scope.branch, .worktree])
    func `phone branch switches retain only worktree scoped blocks`(scope: WorkBlock.Scope) throws {
        let target = SidebarTarget(repository: "repo", repositoryPath: "/repo", branch: "old", path: "/tree")
        let block = WorkBlock(target: target, scope: scope, dependency: .note("Wait"))
        let sidebar = [
            SidebarRepository(name: "repo", owner: nil, worktrees: ["/tree"], entries: [
                SidebarEntry(target: target, status: .blocked, activity: .idle, block: block),
            ]),
        ]
        let session = MobileSession(
            id: "pane",
            name: "agent",
            repository: "repo",
            branch: "new",
            agent: .codexCLI,
            activity: .working,
            directory: "/tree",
        )
        let entry = try #require(session.sidebarEntry(in: sidebar))
        #expect(entry.target.branch == "new")
        #expect(entry.block == (scope == .worktree ? block : nil))
        #expect(entry.status == (scope == .worktree ? .blocked : .working))
    }

    @Test(arguments: [AgentActivity.idle, .working])
    func `phone uses host PR status until the live agent changes`(activity: AgentActivity) {
        let target = SidebarTarget(repository: "repo", repositoryPath: "/repo", branch: "work", path: "/tree")
        let sidebar = [
            SidebarRepository(name: "repo", owner: nil, worktrees: ["/tree"], entries: [
                SidebarEntry(target: target, status: .ciFailing, activity: .idle, block: nil),
            ]),
        ]
        let session = MobileSession(
            id: "pane",
            name: "agent",
            repository: "repo",
            branch: "work",
            agent: .codexCLI,
            activity: activity,
            directory: "/tree",
        )
        #expect(session.sidebarEntry(in: sidebar)?.status == (activity == .idle ? .ciFailing : .working))
        #expect(session.sidebarEntry(in: []) == nil)
    }
}
