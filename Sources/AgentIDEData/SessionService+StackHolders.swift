import AgentIDEDomain
import Foundation

/// Stack branches held by other worktrees, which a restack moves in
/// place. Split from the stack for length.
extension SessionService {
    /// The other worktrees holding the stack's branches, by branch;
    /// throws while any is busy or dirty.
    func quietHolders(
        of stack: BranchStack,
        in worktree: Worktree,
        busyWorktrees: Set<String>,
    ) async throws -> [String: String] {
        let here = Self.resolved(worktree.path)
        let busy = Set(busyWorktrees.map(Self.resolved))
        let all = await git.branchHolders(worktreePath: worktree.path)
        var holders = [String: String]()
        for branch in stack.branches {
            guard let holder = all[branch], Self.resolved(holder) != here else {
                continue
            }

            if busy.contains(Self.resolved(holder)) {
                throw stackError("`" + branch + "`'s agent is busy; rebase once it is idle or done", in: worktree.path)
            }
            if await git.isDirty(worktreePath: holder) {
                throw stackError(
                    "Commit or discard the changes in `" + branch + "`'s worktree first",
                    in: worktree.path,
                )
            }
            holders[branch] = holder
        }
        return holders
    }

    /// Git reports worktrees by resolved path.
    private static func resolved(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    /// Refuses when the worktree that held a branch has since
    /// switched away: the fetch before the rebase is time enough
    /// for an agent or a shell to check something else out, and
    /// rebasing there would take that worktree off what it holds.
    func requireStillHeld(_ branch: String, holders: [String: String], worktreePath: String) async throws {
        guard let holder = holders[branch], await git.currentBranch(worktreePath: holder) != branch else {
            return
        }

        throw stackError("`" + branch + "`'s worktree switched branches; rebase again", in: worktreePath)
    }

    /// Puts the branches a failed restack moved back where they were,
    /// each in the worktree holding it, and the worktree back on the
    /// branch it started on.
    func undoRestack(
        _ moved: [String],
        tips: [String: String],
        holders: [String: String],
        checkedOut: String,
        worktreePath: String,
    ) async {
        await progress("Putting the stack back as it was")
        for branch in moved.reversed() {
            if let tip = tips[branch] {
                try? await git.reset(branch: branch, to: tip, worktreePath: holders[branch] ?? worktreePath)
            }
        }
        try? await git.checkout(branch: checkedOut, worktreePath: worktreePath)
    }
}
