import AgentIDEDomain
import Foundation

/// Stacked branches, all in one worktree: each built on the one
/// below, the bottom on the repository's default branch. The stack is
/// derived from ancestry every time it is asked for, so a branch an
/// agent cuts for itself belongs to the stack as surely as one this
/// app made, and nothing has to be remembered anywhere.
public extension SessionService {
    /// The stack the worktree's branch belongs to, bottom first.
    /// A branch with nothing under or over it comes back as a stack
    /// of one, which every surface treats as no stack at all.
    func stack(for worktree: Worktree) async -> BranchStack {
        let path = worktree.path
        let checkedOut = await git.currentBranch(worktreePath: path) ?? worktree.branch
        let repository = Repository(name: worktree.repositoryName, path: worktree.repositoryPath)
        let baseRef = await git.defaultBaseRef(of: repository)
        let base = baseRef.map(Self.branchName(fromBaseRef:))
        guard let baseRef else {
            return BranchStack(base: nil, branches: [checkedOut], checkedOut: checkedOut)
        }

        // The default branch is not part of any stack, and neither
        // is a branch this worktree has been told to leave out;
        // whatever is checked out is part of it whatever it says.
        let excluded = Set(excludedStackBranches(worktreePath: path))
        let candidates = await git.branches(worktreePath: path)
            .filter { $0 != base && ($0 == checkedOut || excluded.contains($0) == false) }
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
            guard let fork, await git.isAncestor(fork, of: baseRef, worktreePath: path) == false else {
                continue
            }

            await related.append(StackCandidate(
                branch: branch,
                fork: git.commitCount(from: baseRef, to: fork, worktreePath: path),
                tip: git.commitCount(from: baseRef, to: branch, worktreePath: path),
            ))
        }
        // Ordered by where each forks from the line of work, then by
        // how far it has come: that is the order they were built in
        // and the order they must be rebased in.
        // Two branches at the same commit are one branch renamed or
        // one cut by mistake, not two entries: see `collapsingTwins`.
        let branches = await collapsingTwins(related, checkedOut: checkedOut, worktreePath: path)
        // A worktree sitting on the default branch has no stack of
        // its own, and listing the base as its only entry showed the
        // same branch twice wherever both were named.
        let fallback = checkedOut == base ? [] : [checkedOut]
        return BranchStack(
            base: base,
            branches: branches.isEmpty ? fallback : branches,
            checkedOut: checkedOut,
        )
    }

    /// The stack's entries in build order, with branches at one
    /// commit collapsed to one: the checked-out name stands for the
    /// pair, otherwise the one the remote knows, otherwise the one
    /// created first (the other is the rename's leftover or the
    /// mistake), so a restack never replays the same commits twice.
    /// `related` arrives in creation order. Twins rank by one string:
    /// checked-out first, then known to the remote, then creation
    /// order, then name, so no tuple has to be compared.
    private func collapsingTwins(
        _ related: [StackCandidate],
        checkedOut: String,
        worktreePath: String,
    ) async -> [String] {
        var tips = [String: String]()
        var pushed = Set<String>()
        for entry in related {
            tips[entry.branch] = await git.tip(of: entry.branch, worktreePath: worktreePath)
            if await git.remoteBranchExists(worktreePath: worktreePath, branch: entry.branch) {
                pushed.insert(entry.branch)
            }
        }
        let created = Dictionary(uniqueKeysWithValues: related.enumerated().map { ($1.branch, $0) })
        func rank(_ candidate: StackCandidate) -> String {
            let first = candidate.branch == checkedOut ? "0" : "1"
            let known = pushed.contains(candidate.branch) ? "0" : "1"
            return first + known + String(format: "%06d", created[candidate.branch] ?? 0) + candidate.branch
        }
        var seenTips = Set<String>()
        return related
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
    }

    /// The branches a restack would actually move: those not
    /// already sitting on the one below them. Empty means the stack
    /// is in order and the button has nothing to do.
    func branchesOutOfPlace(worktree: Worktree) async -> [String] {
        let path = worktree.path
        let stack = await stack(for: worktree)
        guard let base = stack.base else {
            return []
        }

        var pending = [String]()
        for branch in stack.branches {
            let parent = stack.parent(of: branch) ?? base
            if await git.isAncestor(parent, of: branch, worktreePath: path) == false {
                pending.append(branch)
            }
        }
        return pending
    }

    /// The branches a stack push would actually send: those with
    /// commits the remote does not carry, or no remote branch yet.
    func branchesUnpushed(worktree: Worktree) async -> [String] {
        let path = worktree.path
        let stack = await stack(for: worktree)
        var pending = [String]()
        for branch in stack.branches {
            let remote = "refs/remotes/origin/" + branch
            guard await git.refExists(worktreePath: path, ref: remote) else {
                pending.append(branch)
                continue
            }

            if await git.commitCount(from: remote, to: branch, worktreePath: path) > 0 {
                pending.append(branch)
            }
        }
        return pending
    }

    /// Puts every branch of a stack back on the one below it, bottom
    /// up, signing each commit it replays. A branch already sitting
    /// on its parent is left alone rather than rewritten: an
    /// unnecessary rebase changes every commit's name for nothing.
    /// Nothing half-done survives a failure: the branches already
    /// moved go back to where they were and the worktree returns to
    /// the branch it started on.
    func restack(worktree: Worktree) async throws -> [String] {
        let path = worktree.path
        let stack = await stack(for: worktree)
        try await requireQuiet(worktree: worktree, action: "restack")
        guard let base = stack.base else {
            throw stackError("No default branch to stack on", in: path)
        }

        var tips = [String: String]()
        for branch in stack.branches {
            tips[branch] = await git.tip(of: branch, worktreePath: path)
        }

        var moved = [String]()
        do {
            for branch in stack.branches {
                let parent = stack.parent(of: branch) ?? base
                // Already on its parent: leave every commit's name
                // alone rather than rewriting them to say so.
                if await git.isAncestor(parent, of: branch, worktreePath: path) {
                    continue
                }
                // Where it forked from, recorded before anything
                // moved: without it the replay takes the parent's
                // own commits along a second time.
                guard let forkedFrom = tips[parent] else {
                    continue
                }

                await progress("Rebasing `" + branch + "` onto `" + parent + "`")
                try await git.rebaseSigned(
                    branch: branch,
                    onto: parent,
                    from: forkedFrom,
                    worktreePath: path,
                )
                moved.append(branch)
            }
        } catch {
            await progress("Putting the stack back as it was")
            for branch in moved.reversed() {
                if let tip = tips[branch] {
                    try? await git.reset(branch: branch, to: tip, worktreePath: path)
                }
            }
            try? await git.checkout(branch: stack.checkedOut, worktreePath: path)
            throw error
        }

        try await git.checkout(branch: stack.checkedOut, worktreePath: path)
        return moved
    }

    /// Pushes every branch of a stack, bottom up, so each pull
    /// request's base is on the remote before the branch that points
    /// at it. Each push carries the lease and the includes check the
    /// single-branch push does.
    func pushStack(worktree: Worktree) async throws -> [String] {
        let stack = await stack(for: worktree)
        var pushed = [String]()
        for branch in stack.branches {
            await progress("Pushing `" + branch + "`")
            try await git.push(worktreePath: worktree.path, branch: branch)
            pushed.append(branch)
        }
        return pushed
    }

    /// Pushes the stack, opens a pull request for every branch
    /// missing one, each against the branch below it, and then asks
    /// GitHub to show them as a stack. The pull requests are this
    /// app's own, with its templates, disclosures and titles: only
    /// the last step needs anything GitHub-specific, and that step
    /// keeps no local state of its own.
    func submitStack(worktree: Worktree) async throws -> [String] {
        let stack = await stack(for: worktree)
        _ = try await pushStack(worktree: worktree)
        // Whatever happens, the tab must see what was opened: a
        // throw midway otherwise left the cache saying no pull
        // request existed for one that did.
        defer { pullRequests.invalidateListings(repositoryPath: worktree.repositoryPath) }
        var opened = [String]()
        var numbers = [Int]()
        for branch in stack.branches {
            // Asked of GitHub, not the cache: submitting against a
            // minute-old listing tried to open over a pull request
            // that already existed.
            let listed = try? await github.pullRequests(
                repositoryPath: worktree.repositoryPath,
                scope: .branch(branch),
            )
            if let existing = listed?.first(where: { $0.state == "OPEN" }) {
                numbers.append(existing.number)
                continue
            }

            let parent = stack.parent(of: branch)
            await progress("Opening a pull request for `" + branch + "`")
            let described = await describe(branch: branch, parent: parent ?? stack.base, in: worktree)
            let url = try await github.createPullRequest(
                worktreePath: worktree.path,
                title: described.title,
                body: described.body,
                head: pushDestination(worktree: worktree).head(branch: branch),
                base: parent == stack.base ? nil : parent,
            )
            opened.append(url)
            if let number = url.split(separator: "/").last.flatMap({ Int($0) }) {
                numbers.append(number)
            }
        }
        // Linking needs at least two pull requests, which is what a
        // stack is; the numbers go bottom-up, the order they build.
        if numbers.count >= Self.linkableCount {
            await progress("Linking the stack on GitHub")
            try await github.linkStack(worktreePath: worktree.path, numbers: numbers)
        }
        return opened
    }

    /// A branch's own commits as a pull request: its first commit's
    /// subject titles it, and the rest list the body, which is what
    /// the single-branch form fills in from one commit today.
    private func describe(
        branch: String,
        parent: String?,
        in worktree: Worktree,
    ) async -> (title: String, body: String) {
        guard let parent else {
            return (branch, "")
        }

        let subjects = await git.commitSubjects(from: parent, to: branch, worktreePath: worktree.path)
        guard let title = subjects.last else {
            return (branch, "")
        }

        let rest = subjects.dropLast().reversed().map { "- " + $0 }
        return (title, rest.joined(separator: "\n"))
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
        var metadata = store.load()
        var branches = Set(metadata.stackExclusions[worktreePath] ?? [])
        if excluded {
            branches.insert(branch)
        } else {
            branches.remove(branch)
        }
        metadata.stackExclusions[worktreePath] = branches.isEmpty ? nil : branches.sorted()
        store.save(metadata)
    }

    /// Cuts a new branch on top of the checked-out one, in the same
    /// worktree, which is how a stack grows: the session carries on
    /// where it was, now building on what it just finished.
    func stackBranch(named name: String, on worktree: Worktree) async throws {
        try await requireQuiet(worktree: worktree, action: "branch")
        await progress("Creating `" + name + "` on `" + worktree.branch + "`")
        try await git.createBranch(named: name, worktreePath: worktree.path)
    }

    // MARK: Internal

    /// The fewest pull requests `gh stack link` will link: a stack.
    internal static let linkableCount = 2

    /// Refuses while the worktree holds uncommitted work: a stack
    /// moves by checking branches out, which would take those
    /// changes with it or refuse half way.
    internal func requireQuiet(worktree: Worktree, action _: String) async throws {
        guard await git.isDirty(worktreePath: worktree.path) else {
            return
        }

        throw stackError("Commit or discard the worktree's changes first", in: worktree.path)
    }

    private func stackError(_ message: String, in path: String) -> CommandError {
        CommandError(
            command: "stack in " + path,
            result: ProcessResult(status: 1, standardOutput: "", standardError: message),
        )
    }
}

// MARK: - StackCandidate

/// A branch that shares the line of work, with where it forks from
/// the default branch and how far its tip has come.
private struct StackCandidate {
    let branch: String
    let fork: Int
    let tip: Int
}
