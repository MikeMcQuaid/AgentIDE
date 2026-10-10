import AgentIDEDomain

extension AutofixCoordinator {
    func finish(
        _ attempt: AutofixAttempt,
        summary: PullRequestSummary,
        target: AutofixDriver.Target,
        context: AutofixContext,
    ) async throws {
        let key = context.key
        let store = context.store
        let driver = context.driver
        guard target.session.name == attempt.sessionName, target.session.paneID == attempt.paneID,
              target.worktree.path == attempt.worktreePath, target.worktree.branch == attempt.branch,
              target.session.status == .running, [.done, .idle].contains(target.session.activity),
              let result = try await driver.result(attempt)
        else {
            return
        }
        guard result.attemptID == attempt.id, result.head == attempt.head,
              result.addressedThreadIDs.isSubset(of: Set(attempt.threads.keys)),
              await driver.ready(target, result.commit)
        else {
            store.update { $0.pullRequestAutomation[key]?.lastResult = "Autofix result does not match the worktree" }
            return
        }
        guard let state = store.load().pullRequestAutomation[key], state.attempt?.id == attempt.id else {
            return
        }

        if attempt.sources.contains(.localReview), state.isLocalStage {
            try await finishLocal(attempt, result: result, summary: summary, target: target, context: context)
            return
        }
        guard result.commit != attempt.head else {
            try complete(key: key, message: "Autofix finished without committed fixes", store: store)
            return
        }

        try await markAddressed(attempt, result: result, context: context)
        try await push(attempt, result: result, summary: summary, target: target, context: context)
    }

    func markAddressed(_ attempt: AutofixAttempt, result: AutofixResult, context: AutofixContext) async throws {
        let key = context.key
        let store = context.store
        let driver = context.driver
        guard let state = store.load().pullRequestAutomation[key], state.attempt?.id == attempt.id else {
            return
        }
        guard let fresh = try await driver.summary(state, true), state.matches(fresh),
              fresh.state == "OPEN", let markedHead = fresh.headCommit
        else {
            return
        }

        let threads = Set(attempt.threads.keys).subtracting(attempt.localThreadIDs).isEmpty
            ? [] : try await driver.threads(state, true)
        guard try await driver.summary(state, true)?.headCommit == markedHead else {
            return
        }

        try store.updatePersisting { metadata in
            guard metadata.pullRequestAutomation[key]?.attempt?.id == attempt.id else {
                return
            }

            for id in result.addressedThreadIDs {
                guard metadata.pullRequestAutomation[key]?.resolutions[id] == nil,
                      let mark = attempt.threads[id],
                      let thread = threads.first(where: { $0.resolveID == id }),
                      thread.isResolved == false, thread.comments.last?.id == mark.commentID
                else {
                    continue
                }

                metadata.pullRequestAutomation[key]?.resolutions[id] = PendingThreadResolution(
                    head: markedHead, commentID: mark.commentID,
                )
            }
        }
        try markLocalAddressed(attempt, result: result, context: context)
    }

    func markLocalAddressed(_ attempt: AutofixAttempt, result: AutofixResult, context: AutofixContext) throws {
        let key = context.key
        let store = context.store
        if attempt.sources.contains(.localReview) {
            try store.updatePersisting { metadata in
                guard metadata.pullRequestAutomation[key]?.attempt?.id == attempt.id,
                      var review = metadata.localReviews[attempt.worktreePath],
                      attempt.localThreadIDs.allSatisfy({ id in
                          attempt.threads[id]?.commentID == (review.runID ?? review.revision)
                      })
                else {
                    return
                }

                for index in review.threads.indices where result.addressedThreadIDs.contains(review.threads[index].id) {
                    review.threads[index].isResolved = true
                }
                metadata.localReviews[attempt.worktreePath] = review
            }
        }
    }

    func push(
        _ attempt: AutofixAttempt,
        result: AutofixResult,
        summary: PullRequestSummary,
        target: AutofixDriver.Target,
        context: AutofixContext,
    ) async throws {
        let key = context.key
        let store = context.store
        let driver = context.driver
        guard let state = store.load().pullRequestAutomation[key], state.attempt?.id == attempt.id else {
            return
        }

        let pushKey = PullRequestAutomation.key(for: summary.url)
        guard store.load().pullRequestAutomation[pushKey]?.pushAutomatically == true,
              state.allows(attempt.sources), result.commit != attempt.head
        else {
            try complete(key: key, message: "Autofix finished; changes await a push", store: store)
            return
        }
        guard attempt.pushClaimed == false else {
            try complete(
                key: key,
                message: "Push was already attempted; check GitHub before pushing again",
                store: store,
            )
            return
        }
        guard let fresh = try await driver.summary(state, true), state.matches(fresh),
              fresh.state == "OPEN", fresh.headBranch == attempt.branch, fresh.headCommit == attempt.remoteHead
        else {
            try complete(key: key, message: "GitHub's head changed; automatic push cancelled", store: store)
            return
        }
        guard try claimPush(attempt, pushKey: pushKey, context: context) else {
            return
        }

        do {
            try await driver.push(target, fresh, result.commit)
            try complete(
                key: key,
                message: "Autofix pushed; waiting for GitHub confirmation",
                store: store,
                pushedCommit: result.commit,
                previousHead: attempt.remoteHead,
            )
        } catch {
            store.update { $0.pullRequestAutomation[key]?.isAutomatic = false }
            try complete(key: key, message: "Automatic push failed: " + error.localizedDescription, store: store)
        }
    }

    func claimPush(_ attempt: AutofixAttempt, pushKey: String, context: AutofixContext) throws -> Bool {
        let key = context.key
        let store = context.store
        var claimed = false
        try store.updatePersisting { metadata in
            guard metadata.pullRequestAutomation[key]?.attempt?.id == attempt.id,
                  metadata.pullRequestAutomation[key]?.attempt?.pushClaimed == false,
                  metadata.pullRequestAutomation[pushKey]?.pushAutomatically == true,
                  metadata.pullRequestAutomation[key]?.allows(attempt.sources) == true
            else {
                return
            }

            metadata.pullRequestAutomation[key]?.attempt?.pushClaimed = true
            claimed = true
        }
        return claimed
    }

    func complete(
        key: String, message: String, store: MetadataStore, pushedCommit: String? = nil, previousHead: String? = nil,
    ) throws {
        try store.updatePersisting { value in
            value.pullRequestAutomation[key]?.attempt = nil
            value.pullRequestAutomation[key]?.pushedCommit = pushedCommit
            value.pullRequestAutomation[key]?.pushedFrom = previousHead
            value.pullRequestAutomation[key]?.pending = ""
            value.pullRequestAutomation[key]?.lastResult = message
            if value.pullRequestAutomation[key]?.localRounds?.isComplete == true {
                value.pullRequestAutomation[key]?.localRounds?.lastAttempt = nil
                value.pullRequestAutomation[key]?.localRounds?.commit = nil
            }
            if value.pullRequestAutomation[key]?.canStartRound == false || message.contains("without committed fixes") {
                value.pullRequestAutomation[key]?.isAutomatic = false
            }
        }
    }

    func confirmPush(_ state: PullRequestAutomation, head: String, context: AutofixContext) throws -> Bool {
        guard let pushed = state.pushedCommit else {
            return true
        }
        guard head != state.pushedFrom else {
            context.store.update { value in
                value.pullRequestAutomation[context.key]?.pending = "Waiting for GitHub to confirm the push"
            }
            return false
        }

        try context.store.updatePersisting { value in
            value.pullRequestAutomation[context.key]?.pushedCommit = nil
            value.pullRequestAutomation[context.key]?.pushedFrom = nil
            value.pullRequestAutomation[context.key]?.pending = ""
            value.pullRequestAutomation[context.key]?.lastResult = head == pushed
                ? "Autofix push confirmed by GitHub" : "The head moved after the push; review GitHub's changes"
        }
        return true
    }
}
