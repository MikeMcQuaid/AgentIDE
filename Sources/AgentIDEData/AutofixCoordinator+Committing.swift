extension AutofixCoordinator {
    func requestCommit(
        _ attempt: AutofixAttempt,
        head: String,
        target: AutofixDriver.Target,
        context: AutofixContext,
    ) async throws {
        let key = context.key
        let store = context.store
        guard let state = store.load().pullRequestAutomation[key], state.attempt?.id == attempt.id,
              state.allows(attempt.sources), attempt.pushClaimed == false
        else {
            return
        }
        guard attempt.commitRequestedHead == nil, state.handledEvents.contains("commit:" + head) == false else {
            store.update { value in
                value.pullRequestAutomation[key]?.pending = "Waiting for a clean worktree before accepting the fix"
            }
            return
        }

        var committing = target
        committing.allowsUncommitted = true
        guard await ready(committing, head: head, context: context),
              let fresh = try await context.driver.summary(state, true), state.matches(fresh),
              fresh.state == "OPEN", fresh.headBranch == attempt.branch, fresh.headCommit == attempt.remoteHead,
              await ready(committing, head: head, context: context)
        else {
            return
        }

        var claimed: AutofixAttempt?
        try store.updatePersisting { metadata in
            guard var current = metadata.pullRequestAutomation[key], current.attempt?.id == attempt.id,
                  current.attempt?.commitRequestedHead == nil, current.allows(attempt.sources),
                  current.handledEvents.contains("commit:" + head) == false
            else {
                return
            }

            current.attempt?.commitRequestedHead = head
            current.handledEvents.insert("commit:" + head)
            current.pending = "Asking the agent to commit existing fixes"
            metadata.pullRequestAutomation[key] = current
            claimed = current.attempt
        }
        if let claimed {
            await deliver(claimed, prompt: "", context: context)
        }
    }
}
