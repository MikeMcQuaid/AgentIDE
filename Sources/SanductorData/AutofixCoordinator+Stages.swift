import SanductorDomain

extension AutofixCoordinator {
    func advance(
        _ state: PullRequestAutomation, summary: PullRequestSummary, context: AutofixContext,
    ) async throws {
        let key = context.key
        let store = context.store
        let driver = context.driver
        let target = await driver.target(state, summary)
        if try await reconcileIdleChanges(state, target: target, context: context) {
            return
        }
        guard let target else {
            store.update { value in
                value.pullRequestAutomation[key]?.pending = "Waiting for an agent session on this branch to apply fixes"
            }
            return
        }

        if let attempt = state.attempt {
            try await finish(attempt, target: target, context: context)
            return
        }
        try await gather(state, summary: summary, target: target, context: context)
    }

    func finishLocalStage(_ expected: PullRequestAutomation, context: AutofixContext) throws {
        try context.store.updatePersisting { metadata in
            guard var state = metadata.pullRequestAutomation[context.key], state == expected, state.isAutomatic else {
                return
            }

            state.localRounds = state.localRounds ?? LocalAutofixRounds()
            state.localRounds?.isComplete = true
            state.pending = state.hasRemoteSources ? "Watching for new CI and review feedback" : ""
            if state.hasRemoteSources == false {
                state.isAutomatic = false
                state.loopResult = .finished
                state.lastResult = "Local review and fixes complete"
            }
            metadata.pullRequestAutomation[context.key] = state
        }
    }
}
