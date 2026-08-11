import AgentIDEDomain

/// The repository finder's model surface: listing everything the
/// user can reach on GitHub and jumping to or cloning a pick.
public extension DashboardModel {
    /// The owners listed last time, for an instant first step.
    func cachedOrganisations() -> [String] {
        store.load().organisations
    }

    /// The user's login and organisations, cached for the next
    /// launch. An empty answer keeps the cache: GitHub was probably
    /// unreachable.
    func organisations() async -> [String] {
        let fresh = await service.organisations()
        guard fresh.isEmpty == false else {
            return cachedOrganisations()
        }

        var metadata = store.load()
        metadata.organisations = fresh
        store.save(metadata)
        return fresh
    }

    /// The owner's repositories listed last time, for an instant
    /// second step.
    func cachedRepositories(owner: String) -> [String] {
        store.load().ownerRepositories[owner] ?? []
    }

    /// Every repository under an owner, cached per owner like the
    /// organisations.
    func repositories(owner: String) async -> [String] {
        let fresh = await service.repositories(owner: owner)
        guard fresh.isEmpty == false else {
            return cachedRepositories(owner: owner)
        }

        var metadata = store.load()
        metadata.ownerRepositories[owner] = fresh
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
