import SanductorDomain

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
        let events = state.autofixBots ? try await driver.reviewComments(state, fresh) : []
        if await reviewsReady(state, summary: summary, events: events, driver: driver, fresh: fresh) == false {
            store.update { $0.pullRequestAutomation[key]?.pending = "Waiting for requested reviews" }
            return false
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
                value.pullRequestAutomation[key]?.pending = waiting == 0 ? "Waiting for CI results"
                    : "Waiting for " + String(waiting) + (waiting == 1 ? " CI job" : " CI jobs")
            }
            return false
        }
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
            guard summary.autofixChecks?.isComplete == true else {
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
            let events = try await driver.reviewComments(state, fresh)
            if state.isAutomatic,
               await reviewsReady(state, summary: summary, events: events, driver: driver, fresh: fresh) == false
            {
                return nil
            }
            let threads = try await driver.threads(state, fresh)
            let authors = Set(threads.flatMap(\.comments).filter { $0.authorType == "User" }.map(\.author))
                .union(events.filter { $0.authorType == "User" }.map(\.author))
            let writers = state.autofixReviews ? await driver.writers(state, authors, fresh) : []
            if let summaries = AutofixCandidate.reviewSummaries(
                events, head: summary.headCommit ?? head, state: state, writers: writers,
            ) {
                candidates.append(summaries)
            }
            if let reviews = AutofixCandidate.reviews(threads: threads, head: head, writers: writers, state: state) {
                candidates.append(reviews)
            }
        }
        return AutofixCandidate.combine(candidates)
    }

    func reviewsReady(
        _ state: PullRequestAutomation,
        summary: PullRequestSummary,
        events: [ReviewComment],
        driver: AutofixDriver,
        fresh: Bool,
    ) async -> Bool {
        if state.autofixBots {
            if ReviewBot.allCases.contains(where: { bot in
                summary.requestedReviewers.contains(where: bot.matches)
                    || bot.isWaiting(summary: summary, request: state.botRequest(bot), events: events)
            }) {
                return false
            }
        }
        if state.autofixReviews {
            let requested = summary.requestedReviewers.filter { author in
                ReviewBot.allCases.contains { $0.matches(author) } == false
            }
            return await driver.writers(state, requested, fresh).isEmpty
        }
        return true
    }
}
