import AgentIDEDomain

extension AutofixCoordinator {
    func finishRemoteStage(
        _ state: PullRequestAutomation,
        summary: PullRequestSummary,
        head: String,
        target: AutofixDriver.Target?,
        context: AutofixContext,
    ) async throws {
        guard let fresh = try await context.driver.summary(state, true), state.matches(fresh),
              fresh.state == "OPEN", fresh.headCommit == summary.headCommit,
              fresh.headBranch == summary.headBranch,
              try await feedbackReady(
                  state.stageSelection, summary: fresh, target: target, context: context, fresh: true,
              )
        else {
            return
        }

        var unclaimed = state.stageSelection
        unclaimed.handledEvents = []
        let remaining = try await candidate(
            state: unclaimed, summary: fresh, head: head, fresh: true, driver: context.driver,
        )
        if let remaining, let target, state.canStartRound, state.handledEvents.contains("commit:" + head) == false,
           await context.driver.isDirty(target)
        {
            try await send(remaining, summary: fresh, head: head, target: target, context: context, committing: true)
            return
        }
        guard try await context.driver.summary(state, true)?.headCommit == fresh.headCommit else {
            return
        }

        let clear = remaining == nil && (state.autofixCI == false || fresh.autofixChecks?.results.allSatisfy { check in
            ["SUCCESS", "NEUTRAL", "SKIPPED"].contains(check.conclusion)
        } == true)
        context.store.update { value in
            guard value.pullRequestAutomation[context.key]?.isAutomatic == true,
                  value.pullRequestAutomation[context.key]?.attempt == nil,
                  value.pullRequestAutomation[context.key]?.selectedSources == state.selectedSources
            else {
                return
            }

            value.pullRequestAutomation[context.key]?.pending = ""
            value.pullRequestAutomation[context.key]?.isAutomatic = false
            value.pullRequestAutomation[context.key]?.loopResult = clear ? .finished : .failed
            value.pullRequestAutomation[context.key]?.lastResult = clear
                ? "Success: selected feedback is clear"
                : remaining == nil ? "Still failing: required CI did not pass"
                : state.canStartRound ? "Still failing: selected feedback was already attempted; inspect the fixes"
                : "Still failing: the GitHub round limit was reached with unresolved feedback"
        }
    }
}
