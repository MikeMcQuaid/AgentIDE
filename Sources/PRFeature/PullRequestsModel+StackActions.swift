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
            let moved = try await stacking.restack(worktree)
            // Every branch the restack moved is now behind what the
            // remote has, and GitHub reads a stack whose parents
            // moved as no stack at all: the published ones go back
            // up at once. A branch nobody has pushed stays unpushed,
            // which Push is for.
            if moved.isEmpty == false {
                try await markChecksPending(for: stacking.pushPublished(worktree))
            }
            await loadStack()
            await reload(keepingSelection: true)
            // Done means Push agrees; reporting success with the
            // stack still unsigned took a second press to notice.
            if let unsigned = stacking.unsignedBranches.first {
                report("Restacked, but `" + unsigned + "`'s tip still reads unsigned; "
                    + "check the signing key and hit Rebase again")
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

            recordFinished(onlySigns ? .signed : .rebased, branch: actedBranch ?? worktree.branch)
            note(verb + " " + Self.named(moved) + ".")
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
