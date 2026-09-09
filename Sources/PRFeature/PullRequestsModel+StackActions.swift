import AgentIDEData
import AgentIDEDomain

/// The two things a stack is asked to do as a whole: rebase every
/// branch onto the one below it and push them bottom first. Split
/// from `+Stack` for length.
extension PullRequestsModel {
    /// Puts every branch back on the one below it, from whichever
    /// layer asked, and says what moved; a branch already there is
    /// left alone, so no commit is renamed for nothing.
    func restack() async -> Bool {
        guard let worktree = branchItem?.worktree else {
            return true
        }

        isBranchActionRunning = true
        defer { isBranchActionRunning = false }
        // What it is about to do, before doing it moves the stack
        // and leaves nothing to read it from.
        let onlySigns = stacking.needsRestack == false
        do {
            let (moved, pushed) = try await restackUntilSigned(worktree)
            // Done means Push agrees; reporting success with the
            // stack still unsigned took a second press to notice.
            if let unsigned = stacking.unsignedBranches.first {
                report("Restacked twice, but `" + unsigned + "`'s tip still reads unsigned; "
                    + "check the signing key")
                return false
            }
            let verb =
                if onlySigns {
                    "Signed"
                } else {
                    AppSettings.requiresSignedCommits ? "Rebased and signed" : "Rebased"
                }
            guard moved.isEmpty == false else {
                // Nothing moved, so nothing was done: the button
                // must not claim otherwise.
                setStatus("Already in order.", detail: "The stack was already in order.")
                Self.requestSidebarRefresh()
                return true
            }

            let acted = actedBranch ?? worktree.branch
            var outcomes: Set<BranchOutcome> = [onlySigns ? .signed : .rebased]
            if pushed.contains(acted) {
                outcomes.insert(.pushed)
            }
            recordFinished(outcomes, branch: acted)
            note(verb + " " + Self.named(moved) + (pushed.isEmpty ? "." : "; pushed " + Self.named(pushed) + "."))
            Self.requestSidebarRefresh()
            return true
        } catch {
            report(error.localizedDescription)
            return false
        }
    }

    /// Restacks and reads the stack back, as the lone rebase does: a
    /// tip that reads unsigned is read again after a moment, and one
    /// that still does gets one more restack before the signing key
    /// is questioned. The branches moved, each named once.
    private func restackUntilSigned(_ worktree: Worktree) async throws -> (moved: [String], pushed: [String]) {
        var (moved, pushed) = try await restackAndPushPublished(worktree)
        await readStack()
        if stacking.unsignedBranches.isEmpty == false {
            try? await Task.sleep(for: .milliseconds(Self.signatureSettleMilliseconds))
            await readStack()
        }
        if stacking.unsignedBranches.isEmpty == false {
            let again = try await restackAndPushPublished(worktree)
            moved += again.moved.filter { moved.contains($0) == false }
            pushed += again.pushed.filter { pushed.contains($0) == false }
            await readStack()
        }
        return (moved, pushed)
    }

    /// One restack. Every branch it moved is behind what the remote
    /// has, and GitHub reads a stack whose parents moved as no stack
    /// at all, so the published ones go back up at once; a branch
    /// nobody has pushed stays unpushed, which Push is for.
    private func restackAndPushPublished(_ worktree: Worktree) async throws -> (moved: [String], pushed: [String]) {
        let moved = try await stacking.restack(worktree)
        guard moved.isEmpty == false else {
            return (moved, [])
        }

        let pushed = try await stacking.pushPublished(worktree)
        markChecksPending(for: pushed)
        return (moved, pushed)
    }

    private func readStack() async {
        await loadStack()
        await reload(keepingSelection: true)
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
            markChecksPending(for: pushed)
            recordFinished(.pushed, branch: actedBranch ?? worktree.branch)
            note("Pushed " + Self.named(pushed) + ".")
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
