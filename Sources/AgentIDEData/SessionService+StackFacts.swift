import AgentIDEDomain

/// What a stack would take to put in order and on the remote, read
/// with the stack itself and kept under the same fingerprint. Split
/// from the stack for length.
public extension SessionService {
    /// The stack with what it would take to put it in order and on
    /// the remote, read together: every list is derived from the
    /// same refs, so the one reading that says whether they moved
    /// answers for all of them, and a worktree nothing has touched
    /// costs one process however often the tab asks. Read one list
    /// at a time it was four readings and a process per branch each.
    func stackFacts(for worktree: Worktree) async -> StackFacts {
        let reading = await stackReading(for: worktree)
        // Signing is part of the key: the unsigned list is empty
        // whenever nothing requires a signature.
        let signing = AppSettings.requiresSignedCommits
        let key = reading.fingerprint + String(signing)
        if let known = await StackCache.shared.facts(for: reading.path, derivedFrom: key) {
            PerformanceLog.record(cacheHit: true, "stack-facts#" + reading.path)
            return known
        }

        // The metadata holds the last derivation across a relaunch,
        // which otherwise re-derived every stack from nothing.
        if let saved = store.load().stackFacts[reading.path], saved.fingerprint == reading.fingerprint,
           saved.requiresSigning == signing
        {
            PerformanceLog.record(cacheHit: true, "stack-facts#" + reading.path)
            await StackCache.shared.remember(saved.facts, for: reading.path, derivedFrom: key)
            return saved.facts
        }

        PerformanceLog.record(cacheHit: false, "stack-facts#" + reading.path)
        let stack = await stack(from: reading)
        let facts = await StackFacts(
            stack: stack,
            outOfPlace: outOfPlace(in: stack, path: reading.path),
            unpushed: unpushed(in: stack, path: reading.path),
            unsigned: unsigned(in: stack, path: reading.path),
        )
        await StackCache.shared.remember(facts, for: reading.path, derivedFrom: key)
        store.update { metadata in
            metadata.stackFacts[reading.path] = CachedStackFacts(
                fingerprint: reading.fingerprint,
                requiresSigning: signing,
                facts: facts,
            )
        }
        return facts
    }

    /// The branches a restack would actually move: those not
    /// already sitting on the one below them. Empty means the stack
    /// is in order and the button has nothing to do.
    private func outOfPlace(in stack: BranchStack, path: String) async -> [String] {
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
    private func unpushed(in stack: BranchStack, path: String) async -> [String] {
        var pending = [String]()
        for branch in stack.branches {
            let remote = await remoteBranchRef(worktreePath: path, branch: branch)
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

    /// The stack's branches whose tip is not signed, so the button
    /// that would push them can dim the way a branch's own does
    /// rather than failing on the first one.
    private func unsigned(in stack: BranchStack, path: String) async -> [String] {
        guard AppSettings.requiresSignedCommits else {
            return []
        }

        var unsigned = [String]()
        for branch in stack.branches where await git.isCommitSigned(worktreePath: path, ref: branch) == false {
            unsigned.append(branch)
        }
        return unsigned
    }
}
