import AgentIDEData
import AgentIDEDomain

/// Which branch the tab acts on and whether it can: an entry of a
/// stack is read without being checked out, so what a button reads
/// and what it moves are not always the branch the worktree holds.
/// Split from the actions for length.
extension PullRequestsModel {
    /// What the worktree itself says: its stack, signing, rebase
    /// need, template and checked-out branch. Skipped when moving
    /// between a stack's entries, which share all of it.
    func refreshWorktreeFacts(_ worktree: Worktree) async {
        await loadStack()
        // Gather, then write only while still the newest read: an
        // older reload landing stale signing facts over the rebase's
        // fresh ones is how Push sometimes stayed locked until a
        // second press ran a fresh read.
        stacking.factsGeneration += 1
        let generation = stacking.factsGeneration
        // Before the counts are read: a pull request from a fork has
        // no tracking ref until its remote is named, and everything
        // below counts against one.
        _ = await nameFork(listedWorktree ?? worktree)
        let signed = await checkTipSigned(listedWorktree ?? worktree)
        let tip = await fetchTipCommit(listedWorktree ?? worktree)
        let need = await fetchRebaseNeed(listedWorktree ?? worktree)
        let template = await fetchTemplate(worktree.path)
        let live = await fetchCurrentBranch(worktree.path)
        let labels = availableLabels.isEmpty ? await fetchLabels() : availableLabels
        guard generation == stacking.factsGeneration else {
            return
        }

        tipSignature = signed ? .signed : .unsigned
        // Only the tip moving unpushes a branch: new commits, an
        // amend or a rebase, all of which give the push something
        // to send again. A tip that could not be read has moved
        // nowhere, and clearing the mark on it would relight Push
        // exactly as the stale counts used to.
        if let mark = pushedTip, let tip, mark.branch == (listedBranch ?? worktree.branch), mark.commit != tip {
            pushedTip = nil
        }
        rebaseNeed = need
        availableLabels = labels
        hasTemplate = template != nil
        originalTemplate = template ?? ""
        if prTemplate.isEmpty {
            prTemplate = originalTemplate
        }
        await prefillFromSingleCommit(worktree)
        if let branch = live {
            currentBranch = branch
        }
    }

    /// Fresh counts can mean fresh commits, and nobody has read the
    /// new tip: the signing and rebase facts follow the item, so
    /// Push can never light up on a tip the last read never saw.
    func reverifyBranchFacts(from oldItems: [WorktreeItem]) {
        guard let current = branchItem else {
            return
        }

        let previous = oldItems.first { $0.worktree.path == current.worktree.path }
        guard previous?.aheadOfUpstream != current.aheadOfUpstream
            || previous?.isDirty != current.isDirty
        else {
            return
        }

        tipSignature = .unread
        Task { await refreshWorktreeFacts(current.worktree) }
    }

    /// The rebase button's label names exactly what it would do.
    var rebaseTitle: String {
        guard AppSettings.requiresSignedCommits else {
            return "Rebase on origin"
        }

        return switch rebaseNeed {
        case .sign:
            "Sign commits"

        case .rebaseAndSign:
            "Rebase and sign"

        case .nothing,
             .rebase:
            "Rebase on origin"
        }
    }

    /// Rebase only lights up when it would actually change
    /// something: move the base, sign commits, or both. It acts on
    /// the entry in view, checking it out for the rebase and putting
    /// the worktree back: an entry whose tip is unsigned could
    /// otherwise never be pushed, since Push waits for the signature
    /// only this can give it.
    var canRebase: Bool {
        branchItem != nil && rebaseNeed != SessionService.RebaseNeed.nothing
    }

    func rebaseSigned() async -> Bool {
        guard let worktree = listedWorktree else {
            return true
        }

        isBranchActionRunning = true
        defer { isBranchActionRunning = false }
        // What it is about to do, before doing it moves the branch
        // and leaves nothing to read it from.
        let onlySigns = rebaseNeed == SessionService.RebaseNeed.sign
        do {
            let target = try await performRebase(worktree)
            // A stack member that moves takes the branches above it
            // with it. Left where they were, they fork from the
            // default branch instead of from it, which is not a
            // stack at all: the tab lost the entry that had just
            // moved and showed whichever branch was checked out, so
            // the next press rebased that one instead.
            if stacking.stack.isStacked {
                do {
                    _ = try await stacking.restack(worktree)
                    // Every branch the restack moved is now behind
                    // what the remote has, and GitHub reads a stack
                    // whose parents moved as no stack at all: the
                    // published ones go back up at once. A branch
                    // nobody has pushed stays unpushed, which Push
                    // is for.
                    _ = try await stacking.pushPublished(worktree)
                } catch {
                    report("Rebasing the branches above " + worktree.branch + " failed: "
                        + error.localizedDescription)
                }
            }
            await reload(keepingSelection: true)
            // Done means Push agrees; reporting success with the tip
            // still unsigned took a second press to notice.
            if tipSignature != .signed {
                report("Rebased, but the tip still reads unsigned; check the signing key "
                    + "and hit Rebase again")
                return false
            }
            recordFinished(onlySigns ? .signed : .rebased, branch: listedBranch ?? worktree.branch)
            note("Rebased " + worktree.branch + " on " + target + " and signed it.")
            Self.requestSidebarRefresh()
            return true
        } catch {
            report(error.localizedDescription)
            return false
        }
    }

    /// The one merge action's label, naming exactly what a click
    /// does right now; nil when no open conversation is selected.
    var mergeActionTitle: String? {
        guard let selected, selected.state == "OPEN" else {
            return nil
        }

        // A draft cannot be merged or queued, and GitHub refuses
        // automerge on one too: what a click can do here is take it
        // out of draft, and the label says so.
        if selected.isDraft {
            return "Mark ready"
        }
        if selected.hasAutomerge {
            return hasMergeQueue ? "Dequeue" : "Cancel automerge"
        }
        if Self.isReadyToMerge(selected) {
            return hasMergeQueue ? "Queue" : "Merge"
        }
        // GitHub refuses automerge where a merge queue sets the
        // branch's strategy, and refuses it on a stacked pull
        // request: offering it there only ever ended in that
        // refusal, so the queue's own button waits instead.
        return hasMergeQueue ? "Queue" : "Automerge"
    }

    /// Whether the merge action can run as things stand. Only a
    /// queue's button waits: everywhere else the label already
    /// names something a click can do now, automerge included.
    var canMergeAction: Bool {
        guard let selected, hasMergeQueue, selected.isDraft == false,
              selected.hasAutomerge == false
        else {
            return true
        }

        return Self.isReadyToMerge(selected)
    }

    /// Why the merge action is in the state it is in.
    var mergeActionHelp: String {
        guard canMergeAction else {
            return "This repository's merge queue sets the merge strategy, so there is no "
                + "automerge to ask for: the queue takes it once its checks have passed and "
                + "the reviews it needs are in"
        }

        return "The one merge action for the open conversation: its label names exactly "
            + "what a click does now, and a second click cancels automerge or queueing"
    }

    /// The present-tense form while the merge action runs.
    var mergeActionBusyTitle: String {
        switch mergeActionTitle {
        case "Mark ready":
            "Marking ready"

        case "Dequeue":
            "Dequeuing"

        case "Cancel automerge":
            "Cancelling"

        case "Queue":
            "Queueing"

        case "Merge":
            "Merging"

        default:
            "Enabling automerge"
        }
    }

    /// What an in-app push sent, dimming Push and lighting Open PR
    /// until the branch moves on. Written only by the actions
    /// extension.
    struct PushedTip: Equatable {
        /// The branch pushed, so another entry of a stack never
        /// inherits the mark.
        let branch: String
        /// The commit pushed, since only the tip moving makes a
        /// push necessary again.
        let commit: String
    }

    /// Whether the entry in view is pushed as it stands. A count
    /// read before the push says otherwise for as long as it takes
    /// the next reading to land, which is what flipped Push and
    /// Open PR back and forth after a push.
    var isPushed: Bool {
        guard let mark = pushedTip, let branch = listedBranch ?? branchItem?.worktree.branch else {
            return false
        }

        return mark.branch == branch
    }

    /// Push makes sense with unpushed commits that this tab has not
    /// already pushed and a tip proven GPG signed; an unread tip
    /// dims the button rather than trusting the last answer, since
    /// a click on unverified commits could only end in a refusal.
    /// Nil upstream means nothing was ever pushed. In a stack it is
    /// the listed entry's own commits that are counted, since the
    /// worktree's counts describe whichever branch it has checked
    /// out.
    var canPush: Bool {
        guard branchItem != nil, isPushed == false, tipSignature == .signed else {
            return false
        }

        return hasUnpushedCommits
    }

    /// Whether the listed branch has commits the remote lacks: the
    /// stack's own reading when there is one, the worktree's
    /// upstream count otherwise.
    var hasUnpushedCommits: Bool {
        guard stacking.stack.isStacked, let listed = listedBranch else {
            return (branchItem?.aheadOfUpstream ?? 1) > 0
        }

        return stacking.unpushedBranches.contains(listed)
    }

    /// Why Push is in its current state, for the button's hover:
    /// with nothing to push that is the whole story, and signing
    /// only matters once commits are waiting.
    var pushHelp: String {
        guard branchItem != nil, isPushed == false, hasUnpushedCommits else {
            return "Everything is already pushed"
        }

        return switch tipSignature {
        case .unread:
            "Checking that the tip commit is GPG signed; Push enables once it proves to be"

        case .unsigned:
            "The tip commit is not GPG signed; Rebase on origin signs the branch first"

        case .signed:
            "Push this branch's unpushed commits to origin; a failure reports to the Errors tab"
        }
    }

    /// The branch item's worktree with the checked-out branch
    /// substituted, so pushes and rebases act on what is actually
    /// checked out.
    var actionWorktree: Worktree? {
        worktree(on: currentBranch)
    }

    /// The same worktree with the listed entry's branch: a pull
    /// request is opened for the branch whose form was filled in,
    /// which in a stack need not be the one checked out.
    var listedWorktree: Worktree? {
        worktree(on: listedBranch)
    }

    /// The branch item's worktree as it stands on another of its
    /// branches; every entry of a stack is the same directory.
    func worktree(on branch: String?) -> Worktree? {
        guard let item = branchItem else {
            return nil
        }
        guard let branch, branch != item.worktree.branch else {
            return item.worktree
        }

        return Worktree(
            repositoryName: item.worktree.repositoryName,
            repositoryPath: item.worktree.repositoryPath,
            branch: branch,
            path: item.worktree.path,
        )
    }

    /// Whether one pull request could be merged as it stands: no
    /// draft, no conflict, checks green, and no review outstanding
    /// or refused. An empty review decision is a repository that
    /// asks for none.
    static func isReadyToMerge(_ summary: PullRequestSummary) -> Bool {
        summary.state == "OPEN" && summary.isDraft == false
            && summary.mergeable == "MERGEABLE" && summary.checks == "SUCCESS"
            && ["", "APPROVED"].contains(summary.reviewDecision)
    }
}
