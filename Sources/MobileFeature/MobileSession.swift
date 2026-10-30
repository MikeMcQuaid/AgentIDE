import SanductorDomain

/// One running terminal in the phone's repository navigation.
struct MobileSession: Identifiable, Hashable {
    let id: String
    let name: String
    let repository: String
    let branch: String
    let agent: AgentKind?
    let activity: AgentActivity?
    var directory: String?
    var gitStatus: GitWorktreeStatus?

    static func sortedRepositories(
        _ repositories: [String], sessions: [Self], sidebar: [SidebarRepository] = [],
    ) -> [String] {
        let active = Set(sessions.map(\.repository))
        return repositories.sorted { first, second in
            let firstActive = active.contains(SessionName.slug(first))
            guard firstActive == active.contains(SessionName.slug(second)) else {
                return firstActive
            }

            return (sidebar.firstIndex { $0.name == first } ?? .max)
                < (sidebar.firstIndex { $0.name == second } ?? .max)
        }
    }

    static func sortedSessions(_ sessions: [Self], worktrees: [String]) -> [Self] {
        sessions.sorted { first, second in
            (worktrees.firstIndex { $0 == first.directory } ?? .max)
                < (worktrees.firstIndex { $0 == second.directory } ?? .max)
        }
    }

    static func sessions(in snapshot: HerdrSnapshot, worktrees: [String: GitWorktreeStatus] = [:]) -> [Self] {
        snapshot.workspaces.flatMap { workspace in
            guard SessionName.isSanductor(workspace.label) else {
                return [Self]()
            }

            return snapshot.panes.filter { $0.workspaceID == workspace.workspaceID }.map { pane in
                let worktreeDirectory = pane.cwd.flatMap { $0.isEmpty ? nil : $0 } ?? pane.directory
                return Self(
                    id: pane.paneID,
                    name: workspace.label,
                    repository: SessionName.repositorySlug(of: workspace.label) ?? workspace.label,
                    branch: pane.directory.flatMap { worktrees[$0]?.branch }
                        ?? worktreeDirectory.map { Worktree.directoryBranch(at: $0) }
                        ?? "Unknown branch",
                    agent: pane.agent.flatMap(AgentKind.init(rawValue:)),
                    activity: AgentActivity(herdrStatus: pane.agentStatus),
                    directory: worktreeDirectory,
                    gitStatus: pane.directory.flatMap { worktrees[$0] },
                )
            }
        }
    }
}
