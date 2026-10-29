import AgentIDEDomain

extension MobileModel {
    func repositoryNames(sortedBy sort: RepositorySort) -> [String] {
        sort.sorted(repositories) { name in
            let projected = sidebar.first { $0.name == name }
            return RepositorySort.Key(
                name: projected?.fullName ?? name,
                statuses: sessions.filter { $0.repository == SessionName.slug(name) }.map { sidebarStatus(for: $0) },
                activity: projected?.lastActivityAt ?? 0,
            )
        }
    }

    var sidebarTargets: [SidebarTarget] {
        sidebar.filter { repositories.contains($0.name) }.flatMap(\.entries).map(\.target)
    }

    func sidebarEntry(for session: MobileSession) -> SidebarEntry? {
        session.sidebarEntry(in: sidebar.filter { repositories.contains($0.name) })
    }

    func sidebarStatus(for session: MobileSession) -> SidebarStatus {
        sidebarEntry(for: session)?.status ?? session.sidebarStatus()
    }

    var statusGroups: [(status: SidebarStatus, sessions: [MobileSession])] {
        let ordered = MobileSession.sortedRepositories(repositories, sessions: sessions, sidebar: sidebar)
            .flatMap { repository in
                MobileSession.sortedSessions(
                    sessions.filter { $0.repository == SessionName.slug(repository) },
                    worktrees: sidebar.first { $0.name == repository }?.worktrees ?? [],
                )
            }
        let grouped = Dictionary(grouping: ordered, by: sidebarStatus(for:))
        return SidebarStatus.allCases.compactMap { status in grouped[status].map { (status, $0) } }
    }

    func sidebarRequest(_ request: SidebarRequest) async -> SidebarResponse {
        guard let client = remote, isConnected else {
            return SidebarResponse(error: "Connect to your Mac first.")
        }

        do {
            let response = try await client.sidebarRequest(request)
            let updated = try await client.sidebar()
            guard remote === client else {
                return SidebarResponse(error: "The connection changed. Refresh and try again.")
            }

            if updated != sidebar {
                sidebar = updated
            }
            return response
        } catch {
            return SidebarResponse(error: configuration.errorMessage(error))
        }
    }

    func editBlock(_ block: WorkBlock?, replacing previous: WorkBlock?) async -> String? {
        if let block {
            return await sidebarRequest(.save(block)).error
        }
        if let previous {
            return await sidebarRequest(.remove(previous)).error
        }
        return nil
    }
}
