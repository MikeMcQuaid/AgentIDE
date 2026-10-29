import AgentIDEDomain
import TerminalUI

// MARK: - WorktreeBatchAction

enum WorktreeBatchAction: String {
    case refresh = "Refresh"
    case fetch = "Fetch"
    case fetchAndReset = "Fetch and Reset"
    case cleanUp = "Clean up after merge"
}

// MARK: - DashboardModel

extension DashboardModel {
    func batchItems(for action: WorktreeBatchAction, in items: [WorktreeItem]) -> [WorktreeItem] {
        var repositories = Set<String>()
        return items.filter { item in
            guard item.isPlaceholder == false, item.worktree.isHostDirectory == false,
                  deletingPaths.contains(item.id) == false
            else {
                return false
            }

            switch action {
            case .fetch,
                 .refresh:
                return repositories.insert(item.worktree.repositoryPath).inserted

            case .fetchAndReset:
                return item.worktree.path == item.worktree.repositoryPath

            case .cleanUp:
                return item.worktree.path != item.worktree.repositoryPath || isOffDefaultBranch(item)
            }
        }
    }

    func performBatch(_ action: WorktreeBatchAction, items: [WorktreeItem]) async {
        guard batchAction == nil else {
            return
        }

        let targets = batchItems(for: action, in: items)
        batchAction = action
        defer { batchAction = nil; batchProgress = nil }
        for (index, item) in targets.enumerated() {
            batchProgress = action.rawValue + " (" + String(index + 1) + "/" + String(targets.count) + ")"
            // A preceding action may have refreshed or removed another selected row.
            guard groups.flatMap(\.items).contains(where: { $0.worktree == item.worktree }) else {
                report(item.worktree.branch + " changed or disappeared, so it was left alone.")
                continue
            }

            switch action {
            case .refresh:
                await refreshRepository(path: item.worktree.repositoryPath)

            case .fetch:
                await fetch(item: item)

            case .fetchAndReset:
                await fetchAndReset(item: item)

            case .cleanUp:
                if let refusal = await cleanUp(item: item) {
                    ErrorLog.shared.note(
                        item.worktree.branch + " was left alone: "
                            + (refusal == .dirty ? "uncommitted changes." : "not confirmed merged."),
                        about: item.worktree.repositoryName,
                    )
                }
            }
        }
    }
}
