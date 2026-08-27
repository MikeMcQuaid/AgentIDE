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

    /// The branches with commits the remote lacks, bottom first.
    var unpushedBranches: [String] = []
    var fetch: (Worktree) async -> BranchStack = { worktree in
        BranchStack(base: nil, branches: [worktree.branch], checkedOut: worktree.branch)
    }

    var restack: (Worktree) async throws -> [String] = { _ in [] }
    var push: (Worktree) async throws -> [String] = { _ in [] }
    var submit: (Worktree) async throws -> [String] = { _ in [] }
    var pending: (Worktree) async -> Bool = { _ in false }
    var unpushed: (Worktree) async -> [String] = { _ in [] }
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
            await service.branchesUnpushed(worktree: worktree)
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
        if let worktreePath {
            StackSelection.remember(branch, for: worktreePath)
        }
        // The form is the listed entry's: cleared here, under the
        // new entry's key and without being saved as its draft, so
        // the reload fills it from that entry's own draft or commit
        // rather than seeing the last entry's text and leaving it.
        loadingDraft = true
        prTitle = ""
        prBody = ""
        prTemplate = originalTemplate
        loadingDraft = false
        // Every entry of a stack is one worktree, so nothing git
        // would be asked has changed: the move is a listing swap.
        Task { await reload(keepingSelection: false, refreshingFacts: false) }
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

    /// Fills in the listing cache for the stack's other branches,
    /// so moving to one paints it complete rather than empty. The
    /// answers land in the same cache an ordinary load reads, and
    /// nothing on screen waits for them.
    func prefetchStack() {
        let others = stacking.stack.branches.filter { $0 != listedBranch }
        guard others.isEmpty == false else {
            return
        }

        Task { [weak self] in
            for branch in others {
                guard let self, Task.isCancelled == false else {
                    return
                }

                let listed = try? await pullRequests.listing(
                    repositoryPath: repository.path,
                    scope: scope.listScope(branch: branch),
                )
                // The entry's open pull request warms too: its
                // header and conversation are what clicking shows.
                guard let open = listed?.first(where: { $0.state == "OPEN" }) else {
                    continue
                }

                _ = try? await pullRequests.summary(repositoryPath: repository.path, number: open.number)
                _ = try? await pullRequests.conversation(
                    repositoryPath: repository.path,
                    number: open.number,
                    seededBody: open.body,
                )
            }
        }
    }

    /// Reads the stack the worktree's branch belongs to.
    func loadStack() async {
        guard let worktree = branchItem?.worktree else {
            return
        }

        stacking.stack = await stacking.fetch(worktree)
        stacking.needsRestack = await stacking.pending(worktree)
        stacking.unpushedBranches = await stacking.unpushed(worktree)
        stacking.needsPush = stacking.unpushedBranches.isEmpty == false
        // The entry in view: the one remembered for this worktree,
        // else the first that could have a pull request opened (the
        // top of a stack often cannot yet), else the checked-out
        // branch. A selection naming no branch of this stack goes.
        let remembered = StackSelection.branch(for: worktree.path)
        let chosen = [remembered, firstOpenable, stacking.stack.checkedOut]
            .compactMap(\.self)
            .first { stacking.stack.branches.contains($0) }
        stacking.selected = chosen == stacking.stack.checkedOut ? nil : chosen
        StackSelection.remember(chosen, for: worktree.path)
    }

    /// The branch the listed entry opens against, nil when that is
    /// the default branch. The bottom of a stack targets the default
    /// branch exactly as a lone branch does, whatever sits above it,
    /// and the stack's base is a bare local name that may sit
    /// commits behind the remote, so it is never used as one.
    var listedParent: String? {
        guard stacking.stack.isStacked, let listed = listedBranch,
              let parent = stacking.stack.parent(of: listed), parent != stacking.stack.base
        else {
            return nil
        }

        return parent
    }

    /// Whether the entry on screen is stacked work: only a branch
    /// opening against another branch is. At the bottom of a stack
    /// the tab is the ordinary one branch tab, actions and all,
    /// however many branches sit above it.
    var isStackedEntry: Bool {
        listedParent != nil
    }

    /// The listed entry's own commits as a git range, nil for a
    /// branch on its own, whose range is the default branch's.
    var listedRange: String? {
        guard let listed = listedBranch else {
            return nil
        }

        // A stack entry's span runs from the branch below it; a
        // branch on its own, the bottom of a stack included, from
        // the default branch. Either way it is the listed branch's
        // span, never the checked-out one's, which is what
        // `origin/HEAD..HEAD` would have described. The symbolic
        // form makes the service resolve the fork point.
        return (listedParent ?? "origin/HEAD") + ".." + listed
    }

    /// The lowest entry that can be listed and has no open pull
    /// request yet: the one whose form is worth opening on.
    private var firstOpenable: String? {
        stacking.stack.branches.first { branch in
            guard canList(branch) else {
                return false
            }

            let listed = pullRequests.cachedListing(repositoryPath: repository.path, scope: .branch(branch)) ?? []
            return listed.contains { $0.state == "OPEN" } == false
        }
    }

    /// Whether a stack entry can be listed at all: not while any
    /// branch below it is unpushed, since a pull request above one
    /// cannot exist yet and its form would only be greyed out. The
    /// first unpushed entry itself lists, so it can be pushed and
    /// opened from its own form.
    func canList(_ branch: String) -> Bool {
        guard stacking.stack.isStacked, let index = stacking.stack.branches.firstIndex(of: branch) else {
            return true
        }

        return stacking.stack.branches[..<index].contains { isBlocking($0) } == false
    }

    /// Whether a branch below stops the entries above it: not on the
    /// remote, or on it without an open pull request, since a pull
    /// request above it would target a base GitHub has no pull
    /// request for. The pull request state is the store's cached
    /// listing for that branch, which the stack prefetch fills.
    private func isBlocking(_ branch: String) -> Bool {
        if stacking.unpushedBranches.contains(branch) {
            return true
        }
        let listed = pullRequests.cachedListing(repositoryPath: repository.path, scope: .branch(branch)) ?? []
        return listed.contains { $0.state == "OPEN" } == false
    }

    /// The nearest branch below the listed one that the remote
    /// lacks: a pull request opened above it would target a base
    /// GitHub has never seen, so the form waits for that push.
    var unpushedBelow: String? {
        guard stacking.stack.isStacked, let listed = listedBranch,
              let index = stacking.stack.branches.firstIndex(of: listed)
        else {
            return nil
        }

        return stacking.stack.branches[..<index].last { isBlocking($0) }
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
            pullRequests.invalidateListings(repositoryPath: repository.path)
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
            pullRequests.invalidateListings(repositoryPath: repository.path)
            ErrorLog.shared.note("Pushed " + pushed.joined(separator: ", ") + ".")
            await reload(keepingSelection: true)
        } catch {
            ErrorLog.shared.report(error.localizedDescription)
        }
    }
}
