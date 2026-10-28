import Foundation
import SanductorDomain
import Testing

struct SidebarStatusTests {
    // swiftlint:disable large_tuple - Each case names CI, review, comments and the expected status.
    @Test(arguments: [
        ("FAILURE", "APPROVED", 0, SidebarStatus.ciFailing),
        ("SUCCESS", "CHANGES_REQUESTED", 1, .changesRequested),
        ("SUCCESS", "APPROVED", 1, .unaddressedComments),
        ("SUCCESS", "APPROVED", 0, .readyToMerge),
        ("PENDING", "APPROVED", 0, .waitingForCI),
        ("SUCCESS", "REVIEW_REQUIRED", 0, .waitingForReview),
        ("", "", 0, .open),
    ])
    func `open pull requests group by the next action`(scenario: (String, String, Int, SidebarStatus)) {
        let summary = PullRequestSummary(
            number: 1,
            title: "Work",
            url: "",
            headBranch: "work",
            mergeable: "MERGEABLE",
            reviewDecision: scenario.1,
            checks: scenario.0,
            unresolvedComments: scenario.2,
        )
        #expect(SidebarStatus.status(session: nil, pullRequest: summary, reviewThreadsKnown: true) == scenario.3)
        if scenario.3 == .readyToMerge {
            #expect(SidebarStatus.status(session: nil, pullRequest: summary) == .open)
        }
    }

    // swiftlint:enable large_tuple

    @Test(arguments: ["MERGED", "CLOSED", "OPEN"])
    func `the latest agent or PR event supplies the status but a manual block wins`(state: String) {
        let now = Date()
        let summary = PullRequestSummary(
            number: 1,
            title: "Work",
            url: "",
            headBranch: "work",
            mergeable: "",
            reviewDecision: "",
            checks: "FAILURE",
            state: state,
            stateChangedAt: now,
        )
        let newer = AgentSession(
            name: "agent",
            agent: .codexCLI,
            status: .running,
            activity: .blocked,
            lastActivityAt: now.addingTimeInterval(1),
        )
        let older = AgentSession(
            name: "agent",
            agent: .codexCLI,
            status: .running,
            activity: .working,
            lastActivityAt: now.addingTimeInterval(-1),
        )
        #expect(SidebarStatus.status(session: newer, pullRequest: summary) == .needsInput)
        #expect(SidebarStatus.status(session: older, pullRequest: summary)
            == (state == "MERGED" ? .merged : state == "CLOSED" ? .closed : .ciFailing))
        #expect(SidebarStatus.status(session: newer, pullRequest: summary, blocked: true) == .blocked)
        #expect(SidebarStatus.status(session: newer, pullRequest: summary, launchFailed: true, blocked: true)
            == .launchFailed)
    }

    @Test(arguments: [AgentActivity?.none, .idle], [SidebarStatus.worktree, .branch, .defaultBranch])
    func `idle agents stay distinct from shells and empty worktrees`(
        activity: AgentActivity?, inactiveStatus: SidebarStatus,
    ) throws {
        let agent = AgentSession(name: "agent", agent: .codexCLI, status: .running, activity: activity)
        let shell = AgentSession(name: "shell", agent: nil, status: .running, activity: activity)
        let running = SidebarStatus.status(session: agent, pullRequest: nil)
        let idle = SidebarStatus.status(session: shell, pullRequest: nil, inactiveStatus: inactiveStatus)
        #expect(running.rawValue == "Idle agents")
        #expect(idle == inactiveStatus)
        #expect(SidebarStatus.status(session: nil, pullRequest: nil, inactiveStatus: inactiveStatus) == idle)
        #expect(try #require(SidebarStatus.allCases.firstIndex(of: running))
            < #require(SidebarStatus.allCases.firstIndex(of: idle)))
        #expect(SidebarStatus.status(
            session: AgentSession(name: "agent", agent: .codexCLI, status: .finished), pullRequest: nil,
        ) == .exited)
    }

    @Test
    func `old phone snapshots still decode without statuses`() throws {
        let data = Data(#"[{"name":"repo","worktrees":["/repo"]}]"#.utf8)
        let repositories = try JSONDecoder().decode([SidebarRepository].self, from: data)
        #expect(repositories.first?.entries.isEmpty == true)
        #expect(repositories.first?.lastActivityAt == 0)
        #expect(repositories.first?.defaultBranch == nil)
    }

    @Test
    func `branch blocks follow branches and worktree blocks follow directories`() throws {
        let target = SidebarTarget(repository: "repo", repositoryPath: "/repo", branch: "work", path: "/tree")
        let switched = SidebarTarget(repository: "repo", repositoryPath: "/repo", branch: "other", path: "/tree")
        let moved = SidebarTarget(repository: "repo", repositoryPath: "/repo", branch: "work", path: "/new-tree")
        let branch = WorkBlock(target: target, scope: .branch, dependency: .note("Waiting for designs"))
        let worktree = WorkBlock(target: target, scope: .worktree, dependency: .worktree(moved))
        #expect(branch.applies(to: switched) == false)
        #expect(branch.applies(to: moved))
        #expect(worktree.applies(to: switched))
        #expect(worktree.applies(to: moved) == false)
        #expect(try JSONDecoder().decode(WorkBlock.self, from: JSONEncoder().encode(branch)) == branch)
    }
}
