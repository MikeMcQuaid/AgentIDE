import SanductorDomain

extension AutofixCoordinator {
    func gatherConflicts(
        _ state: PullRequestAutomation,
        summary: PullRequestSummary,
        head: String,
        target: AutofixDriver.Target,
        context: AutofixContext,
    ) async throws -> Bool {
        guard state.isAutomatic, state.hasRemoteSources, summary.mergeable == "CONFLICTING" else {
            return false
        }

        var clean = target
        clean.allowsUncommitted = false
        guard await ready(clean, head: head, context: context) else {
            return true
        }
        guard let candidate = try await conflictCandidate(
            summary: summary, head: head, target: clean, driver: context.driver,
        ) else {
            return false
        }
        guard candidate.events.isDisjoint(with: state.handledEvents) else {
            context.store.update { metadata in
                metadata.pullRequestAutomation[context.key]?.pending =
                    "Conflict rebase already requested; inspect the agent’s result"
            }
            return true
        }

        try await send(candidate, summary: summary, head: head, target: clean, context: context)
        return true
    }

    func conflictCandidate(
        summary: PullRequestSummary, head: String, target: AutofixDriver.Target, driver: AutofixDriver,
    ) async throws -> AutofixCandidate? {
        guard summary.mergeable == "CONFLICTING", summary.baseBranch.isEmpty == false,
              let base = try await driver.conflictBase(target, summary)
        else {
            return nil
        }

        let rebase = AutofixRebase(baseBranch: summary.baseBranch, baseHead: base)
        return AutofixCandidate(
            counts: [.conflicts: 1],
            sources: [.conflicts],
            events: ["rebase:" + head + ":" + rebase.remoteRef + ":" + base],
            text: rebase.prompt(branch: target.worktree.branch, head: head),
            threads: [:],
            rebase: rebase,
        )
    }

    func completeRebase(
        _ attempt: AutofixAttempt, result: AutofixResult, target: AutofixDriver.Target, context: AutofixContext,
    ) async throws -> Bool {
        guard let rebase = attempt.rebase else {
            return true
        }
        guard await context.driver.containsHead(target, rebase.baseHead) else {
            context.store.update { metadata in
                metadata.pullRequestAutomation[context.key]?.pending =
                    "Waiting for the completed rebase on " + rebase.remoteRef
            }
            return false
        }
        guard let state = context.store.load().pullRequestAutomation[context.key], state.attempt?.id == attempt.id
        else {
            return false
        }

        var marks = [String: PendingThreadResolution]()
        for (id, mark) in state.resolutions {
            if let commit = mark.fixCommit, mark.requested == false,
               await context.driver.containsFix(state, commit, attempt.head)
            {
                marks[id] = mark
            }
        }
        try context.store.updatePersisting { metadata in
            guard metadata.pullRequestAutomation[context.key]?.attempt?.id == attempt.id else {
                return
            }

            metadata.pullRequestAutomation[context.key]?.rebasedHeads = [attempt.remoteHead: result.commit]
            for (id, mark) in marks where metadata.pullRequestAutomation[context.key]?.resolutions[id] == mark {
                metadata.pullRequestAutomation[context.key]?.resolutions[id] = PendingThreadResolution(
                    head: mark.head, commentID: mark.commentID, fixCommit: result.commit,
                )
            }
        }
        return true
    }
}
