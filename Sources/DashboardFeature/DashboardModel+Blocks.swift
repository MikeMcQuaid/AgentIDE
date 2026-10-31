import Foundation
import SanductorData
import SanductorDomain

extension DashboardModel {
    func repositoryGroups(sortedBy sort: RepositorySort) -> [RepositoryGroup] {
        sort.sorted(visibleGroups) { group in
            RepositorySort.Key(
                name: group.repository.fullName ?? group.repository.name,
                statuses: group.items.map { sidebarStatus(for: $0) },
                activity: SessionService.repositoryActivity(of: group),
            )
        }
    }

    var sidebarTargets: [SidebarTarget] {
        groups.flatMap(\.items)
            .filter { $0.worktree.isHostDirectory == false && $0.isPlaceholder == false }
            .map { SidebarTarget($0.worktree) }
    }

    func block(for item: WorktreeItem) -> WorkBlock? {
        workBlocks.first { $0.applies(to: SidebarTarget(item.worktree)) }
    }

    func sidebarStatus(for item: WorktreeItem) -> SidebarStatus {
        let pullRequest = pullRequest(for: item)
        return .status(
            session: item.session,
            pullRequest: pullRequest,
            inactiveStatus: .inactiveStatus(
                for: SidebarTarget(item.worktree), defaultBranch: groups.group(holding: item)?.defaultBranch,
            ),
            isHostDirectory: item.worktree.isHostDirectory,
            launchFailed: launchFailure(for: item) != nil,
            blocked: block(for: item) != nil,
            reviewThreadsKnown: pullRequest.map { summary in
                store.load().threadsCache[AppMetadata.threadsKey(
                    repositoryPath: item.worktree.repositoryPath, number: summary.number,
                )] != nil
            } ?? false,
        )
    }

    var statusGroups: [(status: SidebarStatus, items: [WorktreeItem])] {
        let grouped = Dictionary(grouping: visibleGroups.flatMap(\.items), by: sidebarStatus(for:))
        return SidebarStatus.allCases.compactMap { status in
            grouped[status].map { (status, $0) }
        }
    }

    func updateWorkBlocks() {
        let updated = store.load().workBlocks
        if workBlocks != updated {
            workBlocks = updated
        }
        cacheSidebar(groups)
    }

    func refreshWorkBlocks(force: Bool) async {
        guard workBlocks.isEmpty == false,
              force || Date().timeIntervalSince(blocksReadAt)
              >= RefreshCadence.slowed(PullRequestStore.minimumInterval, onBattery: isOnBattery())
        else {
            return
        }

        blocksReadAt = Date()
        await service.resolveWorkBlocks()
        updateWorkBlocks()
    }

    func refreshStatusDetails() async {
        await startStatusDetailsRefresh().value
    }

    @discardableResult
    func startStatusDetailsRefresh() -> Task<Void, Never> {
        if let statusDetailsTask {
            return statusDetailsTask
        }

        let task = Task {
            await readStatusDetails()
            statusDetailsTask = nil
        }
        statusDetailsTask = task
        return task
    }

    private func readStatusDetails() async {
        let before = groups.flatMap(\.items).map { pullRequest(for: $0) }
        let statuses = groups.flatMap(\.items).map { sidebarStatus(for: $0) }
        for item in groups.flatMap(\.items) {
            guard let summary = pullRequest(for: item), summary.state == "OPEN" else {
                continue
            }

            _ = try? await pullRequests.summary(repositoryPath: item.worktree.repositoryPath, number: summary.number)
            _ = try? await pullRequests.conversation(
                repositoryPath: item.worktree.repositoryPath,
                number: summary.number,
                seededBody: summary.body,
            )
        }
        if before != groups.flatMap(\.items).map({ pullRequest(for: $0) })
            || statuses != groups.flatMap(\.items).map({ sidebarStatus(for: $0) })
        {
            pullRequestCacheGeneration += 1
        }
        cacheSidebar(groups)
    }
}
