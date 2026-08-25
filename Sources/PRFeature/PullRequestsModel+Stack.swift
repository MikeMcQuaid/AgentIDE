import AgentIDEData
import AgentIDEDomain
import Foundation
import TerminalUI

// MARK: - StackWork

/// What the tab knows about the stack this branch belongs to: the
/// stack itself, and the work it can be asked to do as a whole.
struct StackWork {
    var stack: BranchStack = .init(base: nil, branches: [], checkedOut: "")

    /// The entry the tab is listing, when it is not the branch the
    /// worktree holds: reading up and down a stack must survive the
    /// reload that asks git which branch is really checked out.
    var selected: String?

    /// What each of the stack's two actions would actually do, so
    /// a button with nothing to do says so by dimming.
    var needsRestack = false
    var needsPush = false
    var fetch: (Worktree) async -> BranchStack = { worktree in
        BranchStack(base: nil, branches: [worktree.branch], checkedOut: worktree.branch)
    }

    var restack: (Worktree) async throws -> [String] = { _ in [] }
    var push: (Worktree) async throws -> [String] = { _ in [] }
    var submit: (Worktree) async throws -> [String] = { _ in [] }
    var pending: (Worktree) async -> Bool = { _ in false }
    var unpushed: (Worktree) async -> Bool = { _ in false }
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
        stacking.submit = { worktree in
            try await service.submitStack(worktree: worktree)
        }
        stacking.pending = { worktree in
            await service.branchesOutOfPlace(worktree: worktree).isEmpty == false
        }
        stacking.unpushed = { worktree in
            await service.branchesUnpushed(worktree: worktree).isEmpty == false
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
        stacking.selected = branch == stacking.stack.checkedOut ? nil : branch
        Task { await reload(keepingSelection: false) }
    }

    /// Whether restacking would move anything: a branch not already
    /// sitting on the one below it.
    var canRestack: Bool {
        stacking.needsRestack
    }

    /// Whether any branch of the stack has commits the remote does
    /// not carry.
    var canPushStack: Bool {
        stacking.needsPush
    }

    /// Whether any branch of the stack still wants a pull request.
    var canSubmitStack: Bool {
        let open = Set(summaries.filter { $0.state == "OPEN" }.map(\.headBranch))
        return stacking.stack.branches.contains { open.contains($0) == false }
    }

    /// Reads the stack the worktree's branch belongs to.
    func loadStack() async {
        guard let worktree = branchItem?.worktree else {
            return
        }

        stacking.stack = await stacking.fetch(worktree)
        // A selection that no longer names a branch of this stack
        // goes, so the tab returns to the worktree's own branch.
        if let selected = stacking.selected, stacking.stack.branches.contains(selected) == false {
            stacking.selected = nil
        }
        stacking.needsRestack = await stacking.pending(worktree)
        stacking.needsPush = await stacking.unpushed(worktree)
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

    /// Pushes the stack, opens whatever pull requests are missing
    /// against the branch below each, and asks GitHub to show them
    /// as a stack.
    func submitStack() async {
        guard let worktree = branchItem?.worktree else {
            return
        }

        do {
            let opened = try await stacking.submit(worktree)
            ErrorLog.shared.note(
                opened.isEmpty
                    ? "The stack is on GitHub already."
                    : "Opened " + String(opened.count) + " pull requests and stacked them.",
            )
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
