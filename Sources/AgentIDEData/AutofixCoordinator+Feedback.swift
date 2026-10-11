import AgentIDEDomain

extension AutofixCoordinator {
    func feedbackReady(
        _ state: PullRequestAutomation,
        summary: PullRequestSummary,
        target: AutofixDriver.Target?,
        context: AutofixContext,
        fresh: Bool = false,
    ) async throws -> Bool {
        let key = context.key
        let store = context.store
        let driver = context.driver
        if state.hasLocalSources {
            guard let target, let collection = try await driver.collect(state, target, false),
                  collection.isPending == false
            else {
                return false
            }

            if let failure = collection.failure {
                store.update { value in
                    value.pullRequestAutomation[key]?.isAutomatic = false
                    value.pullRequestAutomation[key]?.loopResult = .failed
                }
                throw SessionServiceError(failure)
            }
        }
        if state.autofixBots {
            let bot = state.requestedBot(on: summary.headCommit) ?? state.reviewBot
            guard try await botReady(bot, state: state, summary: summary, context: context, fresh: fresh) else {
                store.update { $0.pullRequestAutomation[key]?.pending = "Waiting for " + bot.displayName + "’s review" }
                return false
            }
        }
        if state.autofixCI, summary.autofixChecks?.isComplete != true {
            let checks = summary.autofixChecks
            let complete = Set((checks?.results ?? [])
                .filter { check in
                    check.status == "COMPLETED" && check.conclusion.isEmpty == false
                }
                .map(\.name))
            let unfinished = (checks?.results ?? [])
                .filter { $0.status != "COMPLETED" || $0.conclusion.isEmpty }
                .map(\.name)
            let waiting = (checks?.required ?? []).subtracting(complete).union(unfinished).count
            store.update { value in
                value.pullRequestAutomation[key]?.pending = waiting == 0 ? "Waiting for required CI results"
                    : "Waiting for " + String(waiting) + (waiting == 1 ? " required CI job" : " required CI jobs")
            }
            return false
        }
        return true
    }

    func candidate(
        state: PullRequestAutomation,
        summary: PullRequestSummary,
        head: String,
        fresh: Bool,
        driver: AutofixDriver,
    ) async throws -> AutofixCandidate? {
        var candidates = [AutofixCandidate]()
        if state.autofixCI {
            guard summary.headCommit == head, summary.autofixChecks?.isComplete == true else {
                return nil
            }

            if let checks = AutofixCandidate.checks(summary: summary, state: state) {
                candidates.append(checks)
            }
        }
        if state.autofixLocalReviews, let review = try await driver.localReview(state),
           let local = AutofixCandidate.localReview(review, head: head, state: state)
        {
            candidates.append(local)
        }
        if state.autofixReviews || state.autofixBots {
            let events = state.autofixBots ? try await driver.reviewComments(state, fresh) : []
            guard summary.headCommit == head else {
                return nil
            }

            if state.isAutomatic, state.autofixBots {
                let bot = state.requestedBot(on: head) ?? state.reviewBot
                guard bot.isWaiting(summary: summary, request: state.botRequest(bot), events: events) == false,
                      bot.completion(summary: summary, events: events) != nil
                else {
                    return nil
                }
            }

            if let summaries = AutofixCandidate.reviewSummaries(events, head: head, state: state) {
                candidates.append(summaries)
            }
            let threads = try await driver.threads(state, fresh)
            let writers = state.autofixReviews ? await driver.writers(state, threads, fresh) : []
            if let reviews = AutofixCandidate.reviews(threads: threads, head: head, writers: writers, state: state) {
                candidates.append(reviews)
            }
        }
        return AutofixCandidate.combine(candidates)
    }
}
