import Foundation
@testable import MobileFeature
import SanductorDomain
import Testing

struct MobileSessionTests {
    @Test
    func `desktop ordering keeps active repositories first and ignores unavailable entries`() {
        let sessions = [
            MobileSession(id: "a", name: "a", repository: "a", branch: "main", agent: .codexCLI, activity: nil),
            MobileSession(id: "b", name: "b", repository: "b", branch: "main", agent: .codexCLI, activity: nil),
        ]
        let sidebar = ["Unavailable", "Empty", "B", "A", "B"].map { name in
            SidebarRepository(name: name, owner: nil, worktrees: [])
        }
        #expect(MobileSession.sortedRepositories(
            ["A", "B", "Empty", "New"], sessions: sessions, sidebar: sidebar,
        ) == ["B", "A", "Empty", "New"])
    }

    @Test
    func `worktrees follow the Mac order while retaining all panes and new sessions`() {
        let sessions = ["new", "older", "main", "recent", "older"].enumerated().map { index, branch in
            MobileSession(
                id: String(index),
                name: branch,
                repository: "repo",
                branch: branch,
                agent: .codexCLI,
                activity: nil,
                directory: "/repo/" + branch,
            )
        }
        #expect(MobileSession.sortedSessions(
            sessions, worktrees: ["/repo/main", "/repo/recent", "/repo/older", "/repo/deleted"],
        )
        .map(\.id) == ["2", "3", "1", "4", "0"])
        #expect(MobileSession.sortedSessions(sessions, worktrees: []) == sessions)
    }

    @Test
    func `repositories with sessions come first while retaining their order`() {
        let sessions = [
            MobileSession(
                id: "p1", name: "session", repository: "z-repo", branch: "main", agent: .codexCLI, activity: nil,
            ),
            MobileSession(
                id: "p2", name: "session", repository: "z-repo", branch: "main", agent: .claudeCode, activity: nil,
            ),
            MobileSession(id: "p3", name: "session", repository: "b", branch: "main", agent: .codexCLI, activity: nil),
        ]
        let repositories = ["A", "B", "C", "Z Repo"]
        #expect(MobileSession.sortedRepositories(repositories, sessions: sessions) == ["B", "Z Repo", "A", "C"])
        #expect(MobileSession.sortedRepositories(repositories, sessions: []) == repositories)
    }

    @Test
    func `the visible branch comes from Git rather than the session label`() throws {
        let snapshot = try HerdrSnapshot.decode(Data(#"""
        {"result":{"snapshot":{
          "workspaces":[{"workspace_id":"w1","label":"sanductor--repo--old-slug--claude"}],
          "panes":[{"workspace_id":"w1","pane_id":"w1:p1","agent":"codex",
                    "cwd":"/worktrees/repo/old_slug","foreground_cwd":"/worktrees/repo/old_slug/src"}]
        }}}
        """#.utf8))
        let status = GitWorktreeStatus(porcelain: "# branch.head Feature/new_branch\0# branch.ab +2 -1\0? file\0")
        let session = try #require(MobileSession.sessions(
            in: snapshot, worktrees: ["/worktrees/repo/old_slug/src": status],
        )
        .first)
        #expect(session.branch == "Feature/new_branch")
        #expect(session.agent == .codexCLI)
        #expect(session.gitStatus?.summary == "↑2 ↓1 ±")
        #expect(session.directory == "/worktrees/repo/old_slug")
        #expect(session.id == "w1:p1")
        #expect(MobileSession.sessions(
            in: snapshot,
            worktrees: ["/worktrees/repo/old_slug/src": GitWorktreeStatus(porcelain: "# branch.head (detached)\0")],
        )
        .first?
        .branch == "old_slug")
    }

    @Test
    func `every pane is listed but unrelated herdr workspaces are excluded`() throws {
        let snapshot = try HerdrSnapshot.decode(Data(#"""
        {"result":{"snapshot":{
          "workspaces":[{"workspace_id":"w1","label":"sanductor--repo--branch--claude"},
                        {"workspace_id":"w2","label":"unrelated"}],
          "panes":[{"workspace_id":"w1","pane_id":"w1:p1","agent":"claude","agent_status":"blocked"},
                   {"workspace_id":"w1","pane_id":"w1:p2","agent":"codex","agent_status":"working"},
                   {"workspace_id":"w2","pane_id":"w2:p1"}]
        }}}
        """#.utf8))
        let sessions = MobileSession.sessions(in: snapshot)
        #expect(sessions.map(\.id) == ["w1:p1", "w1:p2"])
        #expect(sessions.map(\.repository) == ["repo", "repo"])
        #expect(sessions.map(\.activity) == [.blocked, .working])
        #expect(sessions.map(\.agent) == [.claudeCode, .codexCLI])
    }
}
