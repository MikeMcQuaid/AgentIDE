extension AutofixCoordinator {
    func completedResult(
        _ attempt: AutofixAttempt, target: AutofixDriver.Target, context: AutofixContext,
    ) async throws -> AutofixResult? {
        let key = context.key
        let store = context.store
        let driver = context.driver
        var result = try await driver.result(attempt)
        if let result, result.attemptID != attempt.id || result.head != attempt.head
            || result.addressedThreadIDs.isSubset(of: Set(attempt.threads.keys)) == false
        {
            store.update { $0.pullRequestAutomation[key]?.lastResult = "Autofix result does not match the worktree" }
            return nil
        }
        if let reported = result {
            if attempt.commitRequestedHead == reported.commit,
               await driver.head(target) != reported.commit
            {
                store.update { $0.pullRequestAutomation[key]?.pending = "Waiting for the agent’s committed result" }
                return nil
            }
            guard let commit = try await currentCommit(
                replacing: reported.commit, target: target, context: context,
            ) else {
                return nil
            }

            result = AutofixResult(
                attemptID: reported.attemptID,
                head: reported.head,
                commit: commit,
                addressedThreadIDs: reported.addressedThreadIDs,
            )
        }
        if await driver.isDirty(target), result != nil || attempt.hasObservedTurn == true {
            try await requestCommit(attempt, head: result?.commit ?? attempt.head, target: target, context: context)
            return nil
        }
        return result
    }

    func reconcileIdleChanges(
        _ state: PullRequestAutomation, target: AutofixDriver.Target?, head: String, context: AutofixContext,
    ) async throws -> Bool {
        guard state.attempt == nil, state.isPreparingExistingWork == false, let target else {
            return false
        }

        let dirty = await context.driver.isDirty(target)
        let localHead = await context.driver.head(target)
        guard dirty || (state.isLocalStage == false && localHead != nil && localHead != head) else {
            return false
        }

        if dirty == false, state.pushAutomatically == false {
            context.store.update { metadata in
                metadata.pullRequestAutomation[context.key]?.pending = "Push committed fixes to continue the loop"
            }
            return true
        }

        try reconsiderChanges(state, context: context)
        return true
    }

    /// A signing-only rewrite preserves the reviewed code; other changes need validation.
    func currentCommit(
        replacing expected: String, target: AutofixDriver.Target, context: AutofixContext,
    ) async throws -> String? {
        guard let state = context.store.load().pullRequestAutomation[context.key] else {
            return nil
        }
        guard let head = await context.driver.head(target) else {
            context.store.update { $0.pullRequestAutomation[context.key]?.pending = "Waiting for the local commit" }
            return nil
        }

        if head == expected {
            return head
        }
        if await context.driver.sameTree(target, expected, head) {
            return head
        }
        try reconsiderChanges(state, context: context)
        return nil
    }

    func reconsiderChanges(_ expected: PullRequestAutomation, context: AutofixContext) throws {
        try context.store.updatePersisting { metadata in
            guard var state = metadata.pullRequestAutomation[context.key], state == expected,
                  state.isAutomatic || state.failedPush?.retryRequested == true
            else {
                return
            }

            state.attempt = nil
            state.failedPush = nil
            state.localRounds?.lastAttempt = nil
            state.localRounds?.commit = nil
            state.collection = nil
            state.preparingExistingWork = true
            state.isAutomatic = true
            state.loopResult = nil
            state.pending = "Local changes detected; checking existing work before continuing"
            metadata.pullRequestAutomation[context.key] = state
        }
    }
}
