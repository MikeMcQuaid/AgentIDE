import SanductorDomain

extension AutofixCoordinator {
    func prepareExistingWork(
        _ state: PullRequestAutomation,
        summary: PullRequestSummary,
        head: String,
        target: AutofixDriver.Target,
        context: AutofixContext,
    ) async throws {
        var checks = state
        checks.feedbackWorktreePath = target.worktree.path
        checks.autofixLocalReviews = false
        guard await ready(target, head: head, context: context),
              try await feedbackReady(checks, summary: summary, target: target, context: context)
        else {
            return
        }

        if let feedback = try await existingCandidate(
            state: state, summary: summary, head: head, target: target, driver: context.driver,
        ) {
            if feedback.sources == [.existingWork], await context.driver.isDirty(target) {
                var unclaimed = state
                unclaimed.handledEvents = []
                if let remaining = try await existingCandidate(
                    state: unclaimed, summary: summary, head: head, target: target, driver: context.driver,
                ), remaining.sources != [.existingWork] {
                    if state.handledEvents.contains("commit:" + head) {
                        try stopExistingWork(state, context: context)
                    } else {
                        try await send(
                            remaining, summary: summary, head: head, target: target, context: context, committing: true,
                        )
                    }
                    return
                }
            }
            try await send(feedback, summary: summary, head: head, target: target, context: context)
            return
        }
        guard try await feedbackReady(checks, summary: summary, target: target, context: context, fresh: true) else {
            return
        }

        let local = state.autofixLocalReviews ? try await context.driver.localReview(checks)?.prompt() : nil
        if await context.driver.isDirty(target) || local != nil {
            try stopExistingWork(state, context: context)
            return
        }
        try context.store.updatePersisting { metadata in
            if metadata.pullRequestAutomation[context.key] == state {
                metadata.pullRequestAutomation[context.key]?.preparingExistingWork = false
            }
        }
        guard let current = context.store.load().pullRequestAutomation[context.key],
              current.isAutomatic, current.isPreparingExistingWork == false
        else {
            return
        }

        try await gather(current, summary: summary, target: target, context: context)
    }

    private func stopExistingWork(_ expected: PullRequestAutomation, context: AutofixContext) throws {
        try context.store.updatePersisting { metadata in
            guard metadata.pullRequestAutomation[context.key] == expected else {
                return
            }

            metadata.pullRequestAutomation[context.key]?.isAutomatic = false
            metadata.pullRequestAutomation[context.key]?.preparingExistingWork = false
            metadata.pullRequestAutomation[context.key]?.loopResult = .failed
            metadata.pullRequestAutomation[context.key]?.pending = ""
            metadata.pullRequestAutomation[context.key]?.lastResult =
                "Existing work was already sent to the agent; inspect its result before starting fresh reviews"
        }
    }

    func deliveryCandidate(
        state: PullRequestAutomation,
        summary: PullRequestSummary,
        head: String,
        target: AutofixDriver.Target,
        driver: AutofixDriver,
    ) async throws -> AutofixCandidate? {
        if state.hasRemoteSources, let remote = summary.headCommit, remote != head,
           await state.acceptsFeedback(from: remote, contains: { await driver.containsHead(target, $0) }) == false
        {
            return nil
        }
        if state.hasRemoteSources,
           let conflicts = try await conflictCandidate(summary: summary, head: head, target: target, driver: driver)
        {
            return conflicts
        }
        if state.isPreparingExistingWork {
            return try await existingCandidate(
                state: state, summary: summary, head: head, target: target, driver: driver,
            )
        }
        return try await candidate(
            state: state.stageSelection, summary: summary, head: head, fresh: true, driver: driver,
        )
    }

    private func existingCandidate(
        state: PullRequestAutomation,
        summary: PullRequestSummary,
        head: String,
        target: AutofixDriver.Target,
        driver: AutofixDriver,
    ) async throws -> AutofixCandidate? {
        var selection = state.stageSelection
        selection.feedbackWorktreePath = target.worktree.path
        if let feedback = try await candidate(
            state: selection, summary: summary, head: head, fresh: true, driver: driver,
        ) {
            return feedback
        }
        let events = state.autofixBots ? try await driver.reviewComments(state, true) : []
        guard await driver.isDirty(target), state.autofixCI == false || summary.autofixChecks?.isComplete == true,
              await reviewsReady(state, summary: summary, events: events, driver: driver, fresh: true)
        else {
            return nil
        }

        let revision = try await driver.revision(target)
        guard revision.isEmpty == false, state.handledEvents.contains("existing-work:" + revision) == false else {
            return nil
        }

        return AutofixCandidate(
            counts: [.existingWork: 1],
            sources: [.existingWork],
            events: ["existing-work:" + revision],
            text: """
            Finish the existing work on this branch before starting fresh reviews.
            Inspect uncommitted changes and local commits, run relevant checks and commit the completed branch work.
            Preserve unrelated edits. If they prevent completion, explain what needs attention; do not discard them.
            Current local head: \(head).
            If the existing commits need no further changes, report the current local head as your completed result.
            Do not push or request reviews. Sanductor will continue the selected stages.
            """,
            threads: [:],
        )
    }
}
