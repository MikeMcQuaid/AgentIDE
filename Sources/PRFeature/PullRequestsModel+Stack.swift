import SanductorData
import SanductorDomain

/// A stack of branches in one worktree, as the pull request tab sees
/// it: which branch is listed and what it would take to put the
/// stack in order; the two things a stack is asked to do as a whole
/// are in `+StackActions`.
extension PullRequestsModel {
    /// Points the stack's work at the service; kept here so the
    /// model's own initialiser stays about pull requests.
    func wireStack(service: SessionService) {
        stacking.facts = { worktree in
            await service.stackFacts(for: worktree)
        }
        stacking.restack = { worktree, busy in
            try await service.restack(worktree: worktree, busyWorktrees: busy)
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
    @discardableResult
    func show(branch: String) -> Task<Void, Never>? {
        // Clearing below is for arriving somewhere new; re-listing
        // the entry already in view wiped typed text.
        guard branch != stacking.selected else {
            return nil
        }

        flushDraft()
        stacking.selected = branch
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
        return Task {
            await reload(keepingSelection: false, refreshingFacts: false)
        }
    }

    /// Whether restacking would change anything: a branch not
    /// already sitting on the one below it, or an unsigned tip that
    /// only the signing rebase can make pushable. Without the
    /// second half an in-place stack with unsigned commits greyed
    /// this button while Push waited on exactly this.
    var canRestack: Bool {
        stack.stackingBlocker == nil && restackBlocker == nil && isBranchActionRunning == false
            && (needsStackRebase || unsignedStackBranches.isEmpty == false)
    }

    /// Why a branch held by another worktree cannot be rebased yet:
    /// its agent is busy. Local changes are stashed during the rebase.
    var restackBlocker: String? {
        restackBlocker(in: mutableStackBranches)
    }

    private func restackBlocker(in branches: [String]) -> String? {
        for branch in branches {
            guard let holder = items.first(where: { $0.worktree.branch == branch && $0.worktree.path != worktreePath })
            else {
                continue
            }

            if busyWorktrees.contains(holder.worktree.path) {
                return "`" + branch + "`'s agent is busy; rebase once it is idle or done"
            }
        }
        return nil
    }

    /// Worktrees whose running agent is not idle or done.
    var busyWorktrees: Set<String> {
        Set(
            items.compactMap { item in
                guard let session = item.session, session.status == .running else {
                    return nil
                }

                return session.activity == .idle || session.activity == .done ? nil : item.worktree.path
            },
        )
    }

    /// The branches needed to publish the listed entry, bottom first.
    private var stackThroughListed: [String] {
        guard let listed = listedBranch, let index = stack.branches.firstIndex(of: listed) else {
            return []
        }

        return Array(stack.branches[...index])
    }

    private var stackPushBranches: [String] {
        (listedBranch.map { stack.branchesToPush(through: $0) } ?? []).filter(mutableStackBranches.contains)
    }

    var unpushedStackBranches: [String] {
        stackPushBranches.filter { stacking.unpushedBranches.contains($0) }
    }

    var needsRestackBeforePush: Bool {
        stackPushBranches.contains { branch in
            stacking.outOfPlaceBranches.contains(branch) || stacking.unsignedBranches.contains(branch)
        }
    }

    /// Whether the selected branches have work to push, waiting for any
    /// busy worktrees among them when they need rebasing.
    var canPushStack: Bool {
        stack.stackingBlocker == nil && isBranchActionRunning == false
            && unpushedBelow == nil
            && unpushedStackBranches.isEmpty == false
            && stackPushBranches.contains(where: stacking.unsignedBranches.contains) == false
            && (needsRestackBeforePush == false || restackBlocker(in: stackPushBranches) == nil)
    }

    /// Why the stack's push is in its current state, said the way a
    /// branch's own push says it.
    var pushStackHelp: String {
        if let blocker = stack.stackingBlocker {
            return blocker
        }
        if let below = unpushedBelow {
            return "Push `" + below + "` below this branch first"
        }
        if needsRestackBeforePush, let blocker = restackBlocker(in: stackPushBranches) {
            return blocker
        }
        guard unpushedStackBranches.isEmpty == false else {
            return "The selected branches are already pushed"
        }
        guard let unsigned = stackPushBranches.first(where: stacking.unsignedBranches.contains) else {
            return "Push the listed branch, those below it and published branches above it, bottom first"
        }

        return unsigned + "'s tip commit is not GPG signed; Rebase signs the stack before pushing"
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

    /// Reads the stack the worktree's branch belongs to. Gathers
    /// first and writes only while still the newest read, so a slow
    /// pass cannot land stale answers over a fresher one's.
    func loadStack() async {
        guard let worktree = branchItem?.worktree else {
            return
        }

        stacking.stackGeneration += 1
        let generation = stacking.stackGeneration
        let facts = await stacking.facts(worktree)
        guard generation == stacking.stackGeneration else {
            return
        }

        stacking.stack = facts.stack
        stacking.outOfPlaceBranches = facts.outOfPlace
        stacking.unpushedBranches = facts.unpushed
        stacking.unsignedBranches = facts.unsigned
        // The entry in view: the one remembered for this worktree,
        // else the first without an open pull request, else the checked-out
        // branch. A selection naming no branch of this stack goes.
        let remembered = StackSelection.branch(for: worktree.path)
        let chosen = [remembered, stack.branches.first { hasOpenPullRequest($0) == false }, stack.checkedOut]
            .compactMap(\.self)
            .first { stacking.stack.branches.contains($0) }
        stacking.selected = chosen
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

    /// Whether the entry on screen belongs to a stack at all, its
    /// bottom included. Rebase and Merge are the stack's from any
    /// layer: rebasing the bottom alone loses the layers above it,
    /// and merging it as a lone pull request fails on a merge
    /// queue, which gh joins through automerge and GitHub refuses
    /// for a stacked pull request.
    var isInStack: Bool {
        stacking.stack.isStacked
    }

    /// Whether every pull request below this entry could merge on
    /// its own: mergeable, checks passed, and approved wherever a
    /// review is required. A stacked merge takes them all at once,
    /// so one that is not ready would take the rest with it.
    /// Read from the enriched summaries the stack's prefetch warms;
    /// an entry not yet read counts as not ready.
    var isStackBelowReady: Bool {
        guard let listed = listedBranch,
              let index = stacking.stack.branches.firstIndex(of: listed)
        else {
            return false
        }

        return stacking.stack.branches[..<index].allSatisfy { branch in
            let listing = pullRequests.cachedListing(repositoryPath: repository.path, scope: .branch(branch)) ?? []
            guard let open = listing.first(where: { $0.state == "OPEN" }),
                  let full = pullRequests.cachedSummary(repositoryPath: repository.path, number: open.number)
            else {
                return false
            }

            return Self.isReadyToMerge(full)
        }
    }

    /// Whether GitHub has the chain this entry sits on: every branch
    /// below it open against the branch below that, which is what a
    /// stack there is made of and what a stacked merge needs.
    /// Derived rather than asked: `gh stack view` knows only stacks
    /// it created and tracked locally, and calls a linked one no
    /// stack at all, so asking it would dim the button forever.
    var isStackLinked: Bool {
        guard let listed = listedBranch,
              let index = stacking.stack.branches.firstIndex(of: listed)
        else {
            return false
        }

        return stacking.stack.branches[...index].enumerated().allSatisfy { position, branch in
            let listing = pullRequests.cachedListing(repositoryPath: repository.path, scope: .branch(branch)) ?? []
            guard position > 0 else {
                // The bottom holds the chain up by existing.
                return listing.contains { $0.state == "OPEN" }
            }

            let below = stacking.stack.branches[position - 1]
            return listing.contains { $0.state == "OPEN" && $0.baseBranch == below }
        }
    }

    /// Whether the stacked merge can run: GitHub holds the chain as
    /// a stack, and everything below is ready to go with it.
    var canMergeStack: Bool {
        stack.stackingBlocker == nil && isStackLinked && isStackBelowReady
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

    /// Whether the store's cached listing shows an open pull request
    /// for a branch; the stack's prefetch is what fills it.
    func hasOpenPullRequest(_ branch: String) -> Bool {
        let listed = pullRequests.cachedListing(repositoryPath: repository.path, scope: .branch(branch)) ?? []
        return listed.contains { $0.state == "OPEN" }
    }

    /// The first lower branch that must be pushed before this entry.
    var unpushedBelow: String? {
        stackThroughListed.dropLast().first { branch in
            mutableStackBranches.contains(branch) && stacking.unpushedBranches.contains(branch)
        }
    }

    /// The first lower branch that needs an open pull request.
    var unopenedBelow: String? {
        stackThroughListed.dropLast().first { hasOpenPullRequest($0) == false }
    }
}
