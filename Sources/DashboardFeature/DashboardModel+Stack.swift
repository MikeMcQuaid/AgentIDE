import AgentIDEData
import AgentIDEDomain
import Foundation

/// The stacks the sidebar knows about. GitHub's own chain of pull
/// requests says where a branch stands once they are open and based
/// on each other; until then the only thing that knows is git, so a
/// stack is derived from the worktree itself and kept for the row to
/// read. Deriving costs a handful of git calls per worktree, so it
/// happens a few worktrees at a time on a slow rota rather than in
/// every poll.
extension DashboardModel {
    /// Derives the stacks that are due, oldest answers first.
    func refreshStacks(of listed: [RepositoryGroup]) async {
        let selectedRepository = selection?.worktree.repositoryPath
        let ready = listed
            .flatMap(\.items)
            .filter { $0.worktree.isHostDirectory == false && $0.isPlaceholder == false }
            .filter { (nextStackDerivation[$0.worktree.path] ?? .distantPast) <= Date() }
        // What is on screen first: the selected repository's rows
        // are the ones whose missing marker is noticed. A partition
        // rather than a sort, which needs an ordering of every pair
        // and had none to give.
        let onScreen = ready.filter { $0.worktree.repositoryPath == selectedRepository }
        let due = (onScreen + ready.filter { $0.worktree.repositoryPath != selectedRepository })
            .prefix(Self.stacksPerRefresh)
        // Each derivation is its own handful of git calls; the due
        // ones run beside each other rather than in a line.
        let derived = await withTaskGroup(of: (String, BranchStack).self) { tasks in
            for item in due {
                tasks.addTask { await (item.worktree.path, self.service.stack(for: item.worktree)) }
            }
            var collected = [(String, BranchStack)]()
            for await result in tasks {
                collected.append(result)
            }
            return collected
        }
        for (path, stack) in derived {
            derivedStacks[path] = stack
            // A branch standing on its own is the common case and
            // the cheap answer to be wrong about for a while, so it
            // is asked about far less often than a real stack.
            let interval = stack.isStacked ? Self.stackInterval : Self.loneInterval
            nextStackDerivation[path] = Date().addingTimeInterval(interval)
        }
    }

    /// The stack git says this worktree holds, when it holds one.
    func derivedStanding(for item: WorktreeItem) -> StackStanding? {
        guard let stack = derivedStacks[item.worktree.path], stack.isStacked,
              let position = stack.branches.firstIndex(of: item.worktree.branch).map({ $0 + 1 })
        else {
            return nil
        }

        return StackStanding(
            position: position,
            height: stack.branches.count,
            base: stack.parent(of: item.worktree.branch),
        )
    }

    // MARK: Private

    /// How long a derived stack is trusted before being asked again,
    /// and how many worktrees one refresh will derive.
    static let stackInterval: TimeInterval = 60
    private static let loneInterval: TimeInterval = 300
    private static let stacksPerRefresh = 8
}
