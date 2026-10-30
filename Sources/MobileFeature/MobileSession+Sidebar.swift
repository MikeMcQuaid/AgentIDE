import SanductorDomain

extension MobileSession {
    func sidebarStatus(inactiveStatus: SidebarStatus = .branch) -> SidebarStatus {
        .status(
            session: AgentSession(name: name, agent: agent, status: .running, activity: activity),
            pullRequest: nil,
            inactiveStatus: inactiveStatus,
        )
    }

    func sidebarEntry(in sidebar: [SidebarRepository]) -> SidebarEntry? {
        guard let projected = sidebar.first(where: { group in
                  SessionName.slug(group.name) == repository && group.entries.contains { $0.target.path == directory }
              }),
              let entry = projected.entries.first(where: { $0.target.path == directory })
        else {
            return nil
        }

        let target = SidebarTarget(
            repository: entry.target.repository,
            repositoryPath: entry.target.repositoryPath,
            branch: branch,
            path: entry.target.path,
        )
        let block = entry.block.flatMap { $0.applies(to: target) ? $0 : nil }
        let inactive = SidebarStatus.inactiveStatus(for: target, defaultBranch: projected.defaultBranch)
        var status = block != nil ? SidebarStatus.blocked
            : entry.target.branch == branch && entry.activity == activity
            ? entry.status : sidebarStatus(inactiveStatus: inactive)
        if [.idleAgent, .worktree, .branch, .defaultBranch].contains(status) {
            status = agent == nil ? inactive : .idleAgent
        }
        return SidebarEntry(target: target, status: status, activity: activity, block: block)
    }
}
