import SanductorDomain

extension AutofixCoordinator {
    func prepareExistingWork(
        _ state: PullRequestAutomation,
        summary: PullRequestSummary,
        head: String,
        target: AutofixDriver.Target,
        context: AutofixContext,
    ) async throws {
        guard await ready(target, head: head, context: context) else {
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
                        try stopExistingWork(context)
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
        var checks = state
        checks.feedbackWorktreePath = target.worktree.path
        checks.autofixLocalReviews = false
        checks.autofixBots = false
        checks.autofixCI = state.autofixCI && head == summary.headCommit
        guard try await feedbackReady(checks, summary: summary, target: target, context: context) else {
            return
        }

        if state.autofixLocalReviews, try await context.driver.localReview(checks)?.prompt() != nil {
            try stopExistingWork(context)
            return
        }
        if await context.driver.isDirty(target) || (state.localWorktreePath == nil && head != summary.headCommit) {
            try stopExistingWork(context)
            return
        }
        try context.store.updatePersisting { metadata in
            if metadata.pullRequestAutomation[context.key]?.isAutomatic == true {
                metadata.pullRequestAutomation[context.key]?.preparingExistingWork = false
            }
        }
        guard let current = context.store.load().pullRequestAutomation[context.key], current.isAutomatic else {
            return
        }

        try await gather(current, summary: summary, target: target, context: context)
    }

    private func stopExistingWork(_ context: AutofixContext) throws {
        try context.store.updatePersisting { metadata in
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
        var selection = state
        selection.feedbackWorktreePath = target.worktree.path
        selection.isAutomatic = false
        if state.autofixLocalReviews, let review = try await driver.localReview(selection),
           let local = AutofixCandidate.localReview(review, head: head, state: selection)
        {
            return local
        }
        selection.autofixLocalReviews = false
        if head == summary.headCommit {
            if state.autofixCI, summary.autofixChecks?.isComplete != true {
                return nil
            }
            if let remote = try await candidate(
                state: selection, summary: summary, head: head, fresh: true, driver: driver,
            ) {
                return remote
            }
        }
        guard await driver.isDirty(target) || (state.localWorktreePath == nil && head != summary.headCommit) else {
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
