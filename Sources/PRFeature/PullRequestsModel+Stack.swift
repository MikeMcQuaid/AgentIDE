import AgentIDEData
import AgentIDEDomain
import Foundation
import TerminalUI

// MARK: - StackWork

/// What the tab knows about the stack this branch belongs to: the
/// stack itself, and the work it can be asked to do as a whole.
struct StackWork {
    var stack: BranchStack = .init(base: nil, branches: [], checkedOut: "")
    var fetch: (Worktree) async -> BranchStack = { worktree in
        BranchStack(base: nil, branches: [worktree.branch], checkedOut: worktree.branch)
    }

    var restack: (Worktree) async throws -> [String] = { _ in [] }
    var push: (Worktree) async throws -> [String] = { _ in [] }
}

/// A stack of branches in one worktree, as the pull request tab sees
/// it: which branch is listed, and the two things a stack is asked
/// to do as a whole.
extension PullRequestsModel {
    /// Points the stack's work at the service; kept here so the
    /// model's own initialiser stays about pull requests.
    func wireStack(service: SessionService) {
        stacking.fetch = { worktree in
            await service.stack(for: worktree)
        }
        stacking.restack = { worktree in
            try await service.restack(worktree: worktree)
        }
        stacking.push = { worktree in
            try await service.pushStack(worktree: worktree)
        }
    }

    /// The stack itself, for the surfaces that show it.
    var stack: BranchStack {
        stacking.stack
    }

    /// Lists a branch of the stack, without checking anything out:
    /// reading up and down a stack is navigation, and moving the
    /// worktree to another branch is a deliberate act of its own.
    func show(branch: String) {
        currentBranch = branch
        Task { await reload() }
    }

    /// Reads the stack the worktree's branch belongs to.
    func loadStack() async {
        guard let worktree = branchItem?.worktree else {
            return
        }

        stacking.stack = await stacking.fetch(worktree)
    }

    /// Puts every branch back on the one below it and says what
    /// moved; a branch already there is left alone, so no commit is
    /// renamed for nothing.
    func restack() async {
        guard let worktree = branchItem?.worktree else {
            return
        }

        do {
            let moved = try await stacking.restack(worktree)
            ErrorLog.shared.note(
                moved.isEmpty
                    ? "The stack was already in order."
                    : "Rebased " + moved.joined(separator: ", ") + ".",
            )
            await loadStack()
            await reload(keepingSelection: true)
        } catch {
            ErrorLog.shared.report(error.localizedDescription)
        }
    }

    /// Pushes the stack bottom up, so each pull request's base is on
    /// the remote before the branch that points at it.
    func pushStack() async {
        guard let worktree = branchItem?.worktree else {
            return
        }

        do {
            let pushed = try await stacking.push(worktree)
            ErrorLog.shared.note("Pushed " + pushed.joined(separator: ", ") + ".")
            await reload(keepingSelection: true)
        } catch {
            ErrorLog.shared.report(error.localizedDescription)
        }
    }
}
