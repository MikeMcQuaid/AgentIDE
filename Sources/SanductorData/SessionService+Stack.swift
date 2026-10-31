import SanductorDomain

/// Stacked branches, in one worktree or several: each built on the one
/// below, the bottom on the repository's default branch. The stack is
/// derived from ancestry every time it is asked for, so a branch an
/// agent cuts for itself belongs to the stack as surely as one this
/// app made, and nothing has to be remembered anywhere.
public extension SessionService {
    /// The stack the worktree's branch belongs to, bottom first.
    /// A branch with nothing under or over it comes back as a stack
    /// of one, which every surface treats as no stack at all.
    func stack(for worktree: Worktree) async -> BranchStack {
        await stack(from: stackReading(for: worktree))
    }

    /// Everything a stack is derived from, read once per question:
    /// where every branch points, which is held, which are left out
    /// and when the config the remotes live in was written, with
    /// one process for the refs. The rota derives a stack for a
    /// worktree at a time all day, and almost none of them have
    /// moved since last time.
    internal struct StackReading {
        let path: String
        let checkedOut: String
        let baseRef: String?
        let excluded: Set<String>
        let fingerprint: String
    }

    internal func stackReading(for worktree: Worktree) async -> StackReading {
        let path = worktree.path
        let checkedOut = await git.currentBranch(worktreePath: path) ?? worktree.branch
        let repository = Repository(name: worktree.repositoryName, path: worktree.repositoryPath)
        let baseRef = await git.defaultBaseRef(of: repository)
        // The default branch is not part of any stack, and neither
        // is a branch this worktree has been told to leave out;
        // whatever is checked out is part of it whatever it says.
        let excluded = Set(excludedStackBranches(worktreePath: path))
        let fingerprint = await git.refFingerprint(worktreePath: path)
            + checkedOut + (baseRef ?? "") + excluded.sorted().joined(separator: ",")
            + (GitClient.configModified(at: path)?.timeIntervalSinceReferenceDate.description ?? "")
            + "#published-branches" // Invalidate stacks without remote branch state.
            + "#queued:" + pullRequests.cachedQueuedBranches(repositoryPath: worktree.repositoryPath)
            .sorted()
            .joined(separator: ",")
        return StackReading(
            path: path,
            checkedOut: checkedOut,
            baseRef: baseRef,
            excluded: excluded,
            fingerprint: fingerprint,
        )
    }

    internal func stack(from reading: StackReading) async -> BranchStack {
        let path = reading.path
        let checkedOut = reading.checkedOut
        let base = reading.baseRef.map(Self.branchName(fromBaseRef:))
        guard let baseRef = reading.baseRef else {
            return await BranchStack(
                base: nil,
                branches: [checkedOut],
                checkedOut: checkedOut,
                stackingBlocker: stackingBlocker(branches: [checkedOut], worktreePath: path),
            )
        }

        if let known = await StackCache.shared.stack(for: path, derivedFrom: reading.fingerprint) {
            PerformanceLog.record(cacheHit: true, "stack#" + path)
            return known
        }
        // The facts the metadata kept across a relaunch carry the
        // stack they were derived from.
        if let saved = store.load().stackFacts[path], saved.fingerprint == reading.fingerprint {
            PerformanceLog.record(cacheHit: true, "stack#" + path)
            await StackCache.shared.remember(saved.facts.stack, for: path, derivedFrom: reading.fingerprint)
            return saved.facts.stack
        }

        PerformanceLog.record(cacheHit: false, "stack#" + path)
        let related = await relatedCandidates(to: reading, base: base, baseRef: baseRef)
        // Ordered by where each forks from the line of work, then by
        // how far it has come: that is the order they were built in
        // and the order they must be rebased in.
        // Two branches at the same commit are one branch renamed or
        // one cut by mistake, not two entries: see `collapsingTwins`.
        let (branches, published) = await collapsingTwins(related, checkedOut: checkedOut, worktreePath: path)
        // A worktree sitting on the default branch has no stack of
        // its own, and listing the base as its only entry showed the
        // same branch twice wherever both were named.
        let fallback = checkedOut == base ? [] : [checkedOut]
        // A checked-out branch collapsed into its twin is still the
        // branch the worktree holds: the twin stands for it, at the
        // same commit, so the actions that move what is checked out
        // stay live rather than dimming on a name that has gone.
        let standingIn = await twin(of: checkedOut, among: branches, worktreePath: path)
        let derived = await BranchStack(
            base: base,
            branches: branches.isEmpty ? fallback : branches,
            checkedOut: standingIn ?? checkedOut,
            stackingBlocker: stackingBlocker(branches: related.map(\.branch) + [checkedOut], worktreePath: path),
            published: published,
        )
        await StackCache.shared.remember(derived, for: path, derivedFrom: reading.fingerprint)
        return derived
    }

    /// The branches sharing the checked-out branch's line of work.
    private func relatedCandidates(to reading: StackReading, base: String?, baseRef: String) async -> [StackCandidate] {
        let path = reading.path
        let checkedOut = reading.checkedOut
        let candidates = await git.branches(worktreePath: path)
            .filter { $0 != base && ($0 == checkedOut || reading.excluded.contains($0) == false) }
        var related = [StackCandidate]()
        for branch in candidates {
            // Related when the two last shared history beyond the
            // default branch: one was cut from the other. What the
            // default branch has since done to either of them is
            // beside the point, and asking that it still be their
            // ancestor threw away every stack cut before the last
            // few merges landed, which is the one a restack exists
            // to put back in order.
            let fork = branch == checkedOut
                ? await git.tip(of: branch, worktreePath: path)
                : await git.mergeBase(branch, checkedOut, worktreePath: path)
            guard let fork,
                  await git.isAncestor(fork, of: baseRef, worktreePath: path) == false,
                  let tipCommit = branch == checkedOut ? fork : await git.tip(of: branch, worktreePath: path)
            else {
                continue
            }

            await related.append(StackCandidate(
                branch: branch,
                fork: git.commitCount(from: baseRef, to: fork, worktreePath: path),
                tip: git.commitCount(from: baseRef, to: branch, worktreePath: path),
                forkCommit: fork,
                tipCommit: tipCommit,
            ))
        }
        return await droppingForks(related, checkedOut: checkedOut, worktreePath: path)
    }

    /// The stack's entries in build order, with branches at one
    /// commit collapsed to one, so a restack never replays the same
    /// commits twice. The one the remote knows stands for the pair,
    /// since that is the one a pull request can be open on and the
    /// other is a rename's leftover or a branch cut by mistake;
    /// failing that the checked-out name, failing that the one
    /// created first. `related` arrives in creation order. Twins
    /// rank by one string: on the remote first, then checked out,
    /// then creation order, then name, so no tuple is compared.
    ///
    /// A worktree checked out on the leftover twin is why the remote
    /// comes first: the branch on screen was the local-only name,
    /// and the pull request open on its pushed twin could not be
    /// reached at all.
    private func collapsingTwins(
        _ related: [StackCandidate],
        checkedOut: String,
        worktreePath: String,
    ) async -> (branches: [String], published: [String]) {
        var tips = [String: String]()
        var pushed = Set<String>()
        for entry in related {
            tips[entry.branch] = entry.tipCommit
            if await git.refExists(
                worktreePath: worktreePath,
                ref: remoteBranchRef(worktreePath: worktreePath, branch: entry.branch),
            ) {
                pushed.insert(entry.branch)
            }
        }
        let created = Dictionary(uniqueKeysWithValues: related.enumerated().map { ($1.branch, $0) })
        func rank(_ candidate: StackCandidate) -> String {
            let known = pushed.contains(candidate.branch) ? "0" : "1"
            let here = candidate.branch == checkedOut ? "0" : "1"
            return unsafe known + here + String(format: "%06d", created[candidate.branch] ?? 0) + candidate.branch
        }
        var seenTips = Set<String>()
        let branches = related
            .sorted { first, second in
                if (first.fork, first.tip) != (second.fork, second.tip) {
                    return (first.fork, first.tip) < (second.fork, second.tip)
                }
                return rank(first) < rank(second)
            }
            .filter { entry in
                guard let tip = tips[entry.branch] else {
                    return true
                }

                return seenTips.insert(tip).inserted
            }
            .map(\.branch)
        return (branches, branches.filter { pushed.contains($0) })
    }

    /// The entry standing in for the checked-out branch when that
    /// name was collapsed away: the twin at the same commit, or nil
    /// when the branch is listed under its own name.
    private func twin(of checkedOut: String, among branches: [String], worktreePath: String) async -> String? {
        guard branches.contains(checkedOut) == false,
              let tip = await git.tip(of: checkedOut, worktreePath: worktreePath)
        else {
            return nil
        }

        for branch in branches where await git.tip(of: branch, worktreePath: worktreePath) == tip {
            return branch
        }
        return nil
    }

    /// Puts every branch of a stack back on the one below it, bottom
    /// up, signing each commit it replays. A branch already sitting
    /// on its parent is left alone rather than rewritten: an
    /// unnecessary rebase changes every commit's name for nothing.
    /// Nothing half-done survives a failure: the branches already
    /// moved go back to where they were and the worktree returns to
    /// the branch it started on. A branch another worktree holds is
    /// rebased there, preserving local changes and refusing busy agents.
    func restack(worktree: Worktree, busyWorktrees: Set<String> = []) async throws -> [String] {
        let path = worktree.path
        _ = try await requireStackable(stack(for: worktree))
        // The bottom entry rebases onto the default branch, which is
        // only worth rebasing onto if the remote is current.
        try await fetchIfStale(repositoryPath: worktree.repositoryPath, workingDirectory: path)
        let stack = try await requireStackable(stack(for: worktree))
        let queued = try await pullRequests.queuedBranches(repositoryPath: worktree.repositoryPath)
        let branches = stack.mutableBranches(queued: queued)
        guard branches.isEmpty == false else {
            return []
        }

        let holders = try await quietHolders(of: branches, in: worktree, busyWorktrees: busyWorktrees)
        guard let base = await stackBaseRef(in: stack, worktreePath: path) else {
            throw stackError("No default branch to stack on", in: path)
        }

        // The base's tip counts as much as any branch's: the bottom
        // entry forks from it, and without it that entry was skipped
        // every time while the button went on saying there was work.
        var tips = [String: String]()
        for branch in [base] + stack.branches {
            tips[branch] = await git.tip(of: branch, worktreePath: path)
        }

        return try await git.preservingChanges(in: [path] + Array(holders.values)) {
            var moved = [String]()
            do {
                for branch in branches {
                    let parentBranch = branch == stack.branches.first ? base : stack.parent(of: branch) ?? base
                    let parent = await queued.contains(parentBranch)
                        ? remoteBranchRef(worktreePath: path, branch: parentBranch) : parentBranch
                    // Already on its parent: leave every commit's name
                    // alone rather than rewriting them to say so —
                    // unless its tip is unsigned while signing is
                    // required, since this rebase is the only thing
                    // that can sign it and Push waits on exactly that.
                    if await stackBranchIsReady(branch, parent: parent, worktreePath: path) {
                        continue
                    }
                    // Where it forked from, recorded before anything
                    // moved: without it the replay takes the parent's
                    // own commits along a second time.
                    guard let forkedFrom = tips[parentBranch] else {
                        continue
                    }

                    await progress("Rebasing `" + branch + "` onto `" + parent + "`")
                    try await requireStillHeld(branch, holders: holders, worktreePath: path)
                    try await rebaseStackBranch(
                        branch: branch,
                        onto: parent,
                        from: forkedFrom,
                        fallback: parent == base && base.hasPrefix("refs/remotes/") ? base : nil,
                        worktreePath: holders[branch] ?? path,
                    )
                    moved.append(branch)
                }
            } catch {
                await undoRestack(moved, tips: tips, holders: holders, checkedOut: stack.checkedOut, worktreePath: path)
                throw error
            }

            try await git.checkout(branch: stack.checkedOut, worktreePath: path)
            return moved
        }
    }

    /// Pushes through the requested branch and published branches above it,
    /// bottom up, so each pull request's base is on the remote first.
    /// Each push integrates remote work and pins its lease just like
    /// the single-branch push.
    func pushStack(worktree: Worktree) async throws -> [String] {
        try await pushStack(worktree: worktree, stack: stack(for: worktree))
    }

    /// The branches this worktree's stack has been told to leave
    /// out. The checked-out branch is never among them: it is the
    /// one branch the worktree undeniably holds.
    func excludedStackBranches(worktreePath: String) -> [String] {
        store.load().stackExclusions[worktreePath] ?? []
    }

    /// Takes a branch out of a worktree's inferred stack, or puts it
    /// back. Nothing about git changes: the branch is left where it
    /// is, and the stack simply stops counting it.
    func setStackExclusion(branch: String, excluded: Bool, worktreePath: String) {
        store.update { metadata in
            var branches = Set(metadata.stackExclusions[worktreePath] ?? [])
            if excluded {
                branches.insert(branch)
            } else {
                branches.remove(branch)
            }
            metadata.stackExclusions[worktreePath] = branches.isEmpty ? nil : branches.sorted()
        }
    }

    /// Cuts a new branch on top of the checked-out one, in the same
    /// worktree, which is how a stack grows: the session carries on
    /// where it was, now building on what it just finished.
    func stackBranch(named name: String, on worktree: Worktree) async throws {
        try await requireStackable(stack(for: worktree))
        await progress("Creating `" + name + "` on `" + worktree.branch + "`")
        try await git.createBranch(named: name, worktreePath: worktree.path)
    }

    // MARK: Internal

    /// The fewest pull requests that make a stack.
    internal static let linkableCount = 2

    internal func stackError(_ message: String, in path: String) -> CommandError {
        CommandError(
            command: "stack in " + path,
            result: ProcessResult(status: 1, standardOutput: "", standardError: message),
        )
    }
}

// MARK: - StackCandidate

/// A branch that shares the line of work, with where it forks from
/// the default branch and how far its tip has come.
struct StackCandidate {
    let branch: String
    let fork: Int
    let tip: Int
    /// Where it last shared history with the checked-out branch.
    let forkCommit: String
    let tipCommit: String
}
