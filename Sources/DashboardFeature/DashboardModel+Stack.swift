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
        let due = listed
            .flatMap(\.items)
            .filter { $0.worktree.isHostDirectory == false && $0.isPlaceholder == false }
            .filter { (nextStackDerivation[$0.worktree.path] ?? .distantPast) <= Date() }
            // What is on screen first: the selected repository's
            // rows are the ones whose missing marker is noticed.
            .sorted { first, _ in first.worktree.repositoryPath == selectedRepository }
            .prefix(Self.stacksPerRefresh)
        for item in due {
            let stack = await service.stack(for: item.worktree)
            derivedStacks[item.worktree.path] = stack
            // A branch standing on its own is the common case and
            // the cheap answer to be wrong about for a while, so it
            // is asked about far less often than a real stack.
            let interval = stack.isStacked ? Self.stackInterval : Self.loneInterval
            nextStackDerivation[item.worktree.path] = Date().addingTimeInterval(interval)
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
    private static let stackInterval: TimeInterval = 60
    private static let loneInterval: TimeInterval = 300
    private static let stacksPerRefresh = 8
}
