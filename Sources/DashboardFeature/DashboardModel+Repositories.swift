import AgentIDEDomain

/// The repository finder's model surface: listing everything the
/// user can reach on GitHub and jumping to or cloning a pick.
public extension DashboardModel {
    /// The repositories listed last time, for an instant finder.
    func cachedAccessibleRepositories() -> [String] {
        store.load().accessibleRepositories
    }

    /// Every repository the user can reach on GitHub, cached for the
    /// next launch. An empty answer keeps the cache: GitHub was
    /// probably unreachable.
    func accessibleRepositories() async -> [String] {
        let fresh = await service.accessibleRepositories()
        guard fresh.isEmpty == false else {
            return cachedAccessibleRepositories()
        }

        var metadata = store.load()
        metadata.accessibleRepositories = fresh
        store.save(metadata)
        return fresh
    }

    /// The cached open issues and pull requests for the pickers.
    func cachedOpenSources(repository: Repository) -> (issues: [IssueSummary], pullRequests: [PullRequestSummary]) {
        let metadata = store.load()
        return (
            metadata.openIssuesCache[repository.path] ?? [],
            metadata.openPullRequestsCache[repository.path] ?? [],
        )
    }

    /// Jumps to a repository, cloning it into the workspace first
    /// when it is not there yet.
    func openRepository(fullName: String) async {
        let name = fullName.split(separator: "/").last.map(String.init) ?? fullName
        if selectMainCheckout(fullName: fullName, name: name) {
            showsRepositoryFinder = false
            return
        }

        do {
            status = "Cloning \(fullName)…"
            _ = try await service.cloneRepository(fullName: fullName)
            await refresh()
            _ = selectMainCheckout(fullName: fullName, name: name)
            showsRepositoryFinder = false
            status = nil
        } catch {
            status = error.localizedDescription
        }
    }

    private func selectMainCheckout(fullName: String, name: String) -> Bool {
        let group = groups.first { candidate in
            candidate.repository.fullName == fullName || candidate.repository.name == name
        }
        guard let group else {
            return false
        }

        selection = group.items.first
        return true
    }
}
