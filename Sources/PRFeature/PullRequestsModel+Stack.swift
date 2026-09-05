import AgentIDEData
import AgentIDEDomain

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
        stacking.pushPublished = { worktree in
            try await service.pushStack(worktree: worktree, publishedOnly: true)
        }
        stacking.pending = { worktree in
            await service.branchesOutOfPlace(worktree: worktree).isEmpty == false
        }
        stacking.unpushed = { worktree in
            await service.branchesUnpushed(worktree: worktree)
        }
        stacking.unsigned = { worktree in
            await service.branchesUnsigned(worktree: worktree)
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
        // Clearing below is for arriving somewhere new; re-listing
        // the entry already in view wiped typed text.
        guard branch != stacking.selected else {
            return
        }

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
        Task { await reload(keepingSelection: false, refreshingFacts: false) }
    }

    /// Whether restacking would change anything: a branch not
    /// already sitting on the one below it, or an unsigned tip that
    /// only the signing rebase can make pushable. Without the
    /// second half an in-place stack with unsigned commits greyed
    /// this button while Push waited on exactly this.
    var canRestack: Bool {
        stacking.needsRestack || stacking.unsignedBranches.isEmpty == false
    }

    /// Whether any branch of the stack has commits the remote does
    /// not carry.
    var canPushStack: Bool {
        stacking.needsPush && stacking.unsignedBranches.isEmpty
    }

    /// Why the stack's push is in its current state, said the way a
    /// branch's own push says it.
    var pushStackHelp: String {
        guard stacking.needsPush else {
            return "Every branch of the stack is already pushed"
        }
        guard let unsigned = stacking.unsignedBranches.first else {
            return "Push every branch of the stack, bottom first"
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
        let derived = await stacking.fetch(worktree)
        let needsRestack = await stacking.pending(worktree)
        let unpushed = await stacking.unpushed(worktree)
        let unsigned = await stacking.unsigned(worktree)
        guard generation == stacking.stackGeneration else {
            return
        }

        stacking.stack = derived
        stacking.needsRestack = needsRestack
        stacking.unpushedBranches = unpushed
        stacking.unsignedBranches = unsigned
        stacking.needsPush = unpushed.isEmpty == false
        // The entry in view: the one remembered for this worktree,
        // else the first that could have a pull request opened (the
        // top of a stack often cannot yet), else the checked-out
        // branch. A selection naming no branch of this stack goes.
        let remembered = StackSelection.branch(for: worktree.path)
        let chosen = [remembered, firstOpenable, stacking.stack.checkedOut]
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

    /// Whether the entry on screen is stacked work: only a branch
    /// opening against another branch is. At the bottom of a stack
    /// the tab is the ordinary one branch tab, actions and all,
    /// however many branches sit above it.
    var isStackedEntry: Bool {
        listedParent != nil
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
              let index = stacking.stack.branches.firstIndex(of: listed), index > 0
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
        isStackLinked && isStackBelowReady
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

            return hasOpenPullRequest(branch) == false
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

        // A branch whose own pull request is already open is always
        // there to be read, whatever sits below it: a lower branch
        // whose pull request was closed under it must not hide one
        // that GitHub is showing.
        guard hasOpenPullRequest(branch) == false else {
            return true
        }

        return stacking.stack.branches[..<index].contains { isBlocking($0) } == false
    }

    /// Whether the store's cached listing shows an open pull request
    /// for a branch; the stack's prefetch is what fills it.
    func hasOpenPullRequest(_ branch: String) -> Bool {
        let listed = pullRequests.cachedListing(repositoryPath: repository.path, scope: .branch(branch)) ?? []
        return listed.contains { $0.state == "OPEN" }
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

        return hasOpenPullRequest(branch) == false
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
    func restack() async -> Bool {
        guard let worktree = branchItem?.worktree else {
            return true
        }

        isBranchActionRunning = true
        defer { isBranchActionRunning = false }
        do {
            let moved = try await stacking.restack(worktree)
            await loadStack()
            await reload(keepingSelection: true)
            // Done means Push agrees; reporting success with the
            // stack still unsigned took a second press to notice.
            if let unsigned = stacking.unsignedBranches.first {
                report("Restacked, but " + unsigned + "'s tip still reads unsigned; "
                    + "check the signing key and hit Rebase again")
                return false
            }
            let verb = AppSettings.requiresSignedCommits ? "Rebased and signed" : "Rebased"
            setStatus(
                moved.isEmpty ? "Already in order." : verb + ".",
                detail: moved.isEmpty
                    ? "The stack was already in order."
                    : verb + " " + moved.joined(separator: ", ") + ".",
            )
            Self.requestSidebarRefresh()
            return true
        } catch {
            report(error.localizedDescription)
            return false
        }
    }

    /// Pushes the stack bottom up, so each pull request's base is on
    /// the remote before the branch that points at it.
    func pushStack() async -> Bool {
        guard let worktree = branchItem?.worktree else {
            return true
        }

        isBranchActionRunning = true
        defer { isBranchActionRunning = false }
        do {
            let pushed = try await stacking.push(worktree)
            pullRequests.invalidateListings(repositoryPath: repository.path)
            setStatus("Pushed.", detail: "Pushed " + pushed.joined(separator: ", ") + ".")
            Self.requestSidebarRefresh()
            await reload(keepingSelection: true)
            refreshAfterPush()
            return true
        } catch {
            report(error.localizedDescription)
            return false
        }
    }
}
