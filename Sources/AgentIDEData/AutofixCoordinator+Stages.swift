import AgentIDEDomain

extension AutofixCoordinator {
    func finishLocal(
        _ attempt: AutofixAttempt,
        result: AutofixResult,
        summary: PullRequestSummary,
        target: AutofixDriver.Target,
        context: AutofixContext,
    ) async throws {
        if result.commit != attempt.head {
            try await markAddressed(attempt, result: result, context: context)
            try context.store.updatePersisting { metadata in
                guard var state = metadata.pullRequestAutomation[context.key], state.attempt?.id == attempt.id else {
                    return
                }

                state.localRounds = state.localRounds ?? LocalAutofixRounds(started: max(1, state.roundsStarted))
                state.localRounds?.lastAttempt = attempt
                state.localRounds?.commit = result.commit
                metadata.pullRequestAutomation[context.key] = state
            }
        }
        guard let state = context.store.load().pullRequestAutomation[context.key] else {
            return
        }

        if state.canStartRound == false {
            try await finishLocalStage(summary: summary, target: target, context: context)
        } else if result.commit != attempt.head {
            try complete(key: context.key, message: "Local fix committed; reviewing again", store: context.store)
        } else {
            try await finishLocalStage(summary: summary, target: target, context: context)
        }
    }

    func finishLocalStage(
        summary: PullRequestSummary, target: AutofixDriver.Target, context: AutofixContext,
    ) async throws {
        let key = context.key
        var finished: PullRequestAutomation?
        try context.store.updatePersisting { metadata in
            guard var state = metadata.pullRequestAutomation[key], state.isAutomatic, state.isLocalStage,
                  metadata.pullRequestAutomation.allSatisfy({ entry in
                      entry.key == key || entry.value.attempt?.worktreePath != target.worktree.path
                  })
            else {
                return
            }

            state.localRounds = state.localRounds ?? LocalAutofixRounds()
            state.localRounds?.isComplete = true
            state.attempt = state.localRounds?.lastAttempt
            metadata.pullRequestAutomation[key] = state
            finished = state
        }
        guard let finished else {
            return
        }

        if finished.localWorktreePath != nil {
            try context.store.updatePersisting { $0.pullRequestAutomation[key]?.isAutomatic = false }
            try complete(key: key, message: "Local review and fixes complete", store: context.store)
            return
        }
        guard let attempt = finished.attempt, let commit = finished.localRounds?.commit else {
            try complete(key: key, message: "Local stage complete", store: context.store)
            return
        }
        guard await ready(target, head: commit, context: context) else {
            return
        }

        try await push(
            attempt,
            result: AutofixResult(attemptID: attempt.id, head: attempt.head, commit: commit, addressedThreadIDs: []),
            summary: summary,
            target: target,
            context: context,
        )
    }
}
