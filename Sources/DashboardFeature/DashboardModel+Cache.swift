import AgentIDEData
import AgentIDEDomain
import Foundation

/// The sidebar the last run left behind: written on every
/// reading and painted before the first one, so the window opens
/// on its own rows and its own selection rather than on an empty
/// frame. Only what herdr owns arrives late.
extension DashboardModel {
    /// Seeds the pickers with the models each CLI reported last
    /// time, so they open on the real list while the CLI is asked
    /// again in the background.
    /// Asks each CLI its models, beside the others, only when its
    /// version has moved since the last answer.
    func discoverModels() async {
        // Keyed by the CLI's version and, where its list lives in a
        // cache, that file's modification time: both read from the
        // host in a few milliseconds, where asking the agent itself
        // is twenty seconds of sandbox launch. The cache's time is
        // what catches a model the server added under a version that
        // had not moved.
        let known = store.load().discoveredModelsVersion
        await withTaskGroup(of: (AgentKind, String?, [String]?).self) { tasks in
            for agent in AgentKind.allCases {
                tasks.addTask {
                    let version = await self.service.modelListingStamp(for: agent)
                    guard version == nil || version != known[agent.rawValue] else {
                        return (agent, version, nil)
                    }

                    return await (agent, version, self.service.discoverModels(for: agent))
                }
            }
            // Collected first and stored in one step: the probes
            // take seconds each, and metadata loaded before them is
            // stale by the time they answer.
            var discovered = [(agent: AgentKind, version: String?, models: [String])]()
            for await (agent, version, models) in tasks {
                guard let models else {
                    continue
                }

                discoveredModels[agent] = models
                discovered.append((agent, version, models))
            }
            store.update { metadata in
                for entry in discovered {
                    metadata.discoveredModels[entry.agent.rawValue] = entry.models
                    metadata.discoveredModelsVersion[entry.agent.rawValue] = entry.version
                }
            }
        }
    }

    /// Reads what each agent calls its own models, which costs a
    /// file read apiece and no sandbox launch at all.
    func readModelNames() {
        for agent in AgentKind.allCases {
            let names = service.modelNames(for: agent)
            if names.isEmpty == false {
                modelNames[agent] = names
            }
        }
    }

    func restoreDiscoveredModels() {
        for (raw, models) in store.load().discoveredModels {
            // Only what the agent itself can report: anything
            // remembered for an agent with no listing was scraped
            // out of its prose by an earlier release.
            if let agent = AgentKind(rawValue: raw), service.reportsModels(agent) {
                discoveredModels[agent] = models
            }
        }
    }

    /// Paints the remembered sidebar, selection included.
    func restoreCachedSidebar() {
        let cached = store.load().cachedSidebar
        groups = cached.map { cached in
            let repository = Repository(name: cached.name, path: cached.path, fullName: cached.fullName)
            let items = cached.worktrees.map { worktree in
                WorktreeItem(
                    worktree: Worktree(
                        repositoryName: cached.name,
                        repositoryPath: cached.path,
                        branch: worktree.branch,
                        path: worktree.path,
                        isHostDirectory: worktree.isHostDirectory,
                    ),
                    session: nil,
                    isDirty: worktree.isDirty,
                    aheadOfUpstream: worktree.aheadOfUpstream,
                    hasUnread: false,
                    aheadOfDefault: worktree.aheadOfDefault,
                    behindDefault: worktree.behindDefault,
                    behindUpstream: worktree.behindUpstream,
                    lastActivityAt: worktree.lastActivityAt,
                )
            }
            return RepositoryGroup(repository: repository, items: items, defaultBranch: cached.defaultBranch)
        }
        // The stacks the last run derived come back with the rows,
        // and count as fresh for one interval: the first reading
        // otherwise derived every one of them in its first second.
        for worktree in cached.flatMap(\.worktrees) where worktree.stackCheckedOut != nil {
            derivedStacks[worktree.path] = BranchStack(
                base: worktree.stackBase,
                branches: worktree.stackBranches,
                checkedOut: worktree.stackCheckedOut ?? worktree.branch,
            )
            nextStackDerivation[worktree.path] = Date().addingTimeInterval(Self.stackInterval)
        }
        awaitedSessions = Set(
            cached.flatMap(\.worktrees).filter(\.hasSession).map(\.path),
        )
        if groups.isEmpty == false {
            hasLoaded = true
            let stored = UserDefaults.standard.string(forKey: Self.selectedWorktreeKey)
            selection = groups.flatMap(\.items).first { $0.worktree.path == stored }
            hasRestoredSelection = selection != nil
        }
    }

    func cacheSidebar(_ groups: [RepositoryGroup]) {
        // Placeholders are what a creation looks like while it runs;
        // remembering one meant a failed creation came back on every
        // launch as a row nothing could delete.
        let real = groups.map { group in
            var kept = group
            kept.items = group.items.filter { $0.isPlaceholder == false }
            return kept
        }
        let cached = real.map { group in
            var cached = CachedRepository()
            cached.name = group.repository.name
            cached.fullName = group.repository.fullName
            cached.path = group.repository.path
            cached.defaultBranch = group.defaultBranch
            cached.worktrees = group.items.map { item in
                var worktree = CachedWorktree()
                worktree.branch = item.worktree.branch
                worktree.path = item.worktree.path
                worktree.isHostDirectory = item.worktree.isHostDirectory
                worktree.isDirty = item.isDirty
                worktree.aheadOfUpstream = item.aheadOfUpstream
                worktree.aheadOfDefault = item.aheadOfDefault
                worktree.behindDefault = item.behindDefault
                worktree.behindUpstream = item.behindUpstream
                worktree.lastActivityAt = item.lastActivityAt
                worktree.hasSession = item.session != nil
                if let stack = derivedStacks[item.worktree.path] {
                    worktree.stackBase = stack.base
                    worktree.stackBranches = stack.branches
                    worktree.stackCheckedOut = stack.checkedOut
                }
                return worktree
            }
            return cached
        }
        store.update { $0.cachedSidebar = cached }
    }
}
