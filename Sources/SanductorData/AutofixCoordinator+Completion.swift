extension AutofixCoordinator {
    func finish(
        _ attempt: AutofixAttempt,
        target: AutofixDriver.Target,
        context: AutofixContext,
    ) async throws {
        let key = context.key
        let store = context.store
        guard target.session.name == attempt.sessionName, target.session.paneID == attempt.paneID,
              target.worktree.path == attempt.worktreePath, target.worktree.branch == attempt.branch,
              target.session.status == .running
        else {
            return
        }

        if target.session.activity == .working, attempt.hasObservedTurn != true {
            store.update { value in
                if value.pullRequestAutomation[key]?.attempt?.id == attempt.id {
                    value.pullRequestAutomation[key]?.attempt?.hasObservedTurn = true
                }
            }
        }
        guard [.done, .idle].contains(target.session.activity),
              let result = try await completedResult(attempt, target: target, context: context),
              await ready(target, head: result.commit, context: context),
              let state = store.load().pullRequestAutomation[key], state.attempt?.id == attempt.id,
              try await completeRebase(attempt, result: result, target: target, context: context),
              try await markAddressed(attempt, result: result, context: context)
        else {
            return
        }

        try store.updatePersisting { metadata in
            guard metadata.pullRequestAutomation[key]?.attempt?.id == attempt.id else {
                return
            }

            metadata.pullRequestAutomation[key]?.preparingExistingWork = false
            if attempt.sources.contains(.localReview), result.commit == attempt.head {
                metadata.pullRequestAutomation[key]?.localRounds?.isComplete = true
            }
            metadata.pullRequestAutomation[key]?.attempt = nil
            metadata.pullRequestAutomation[key]?.pending = ""
            metadata.pullRequestAutomation[key]?.lastResult = result.commit == attempt.head
                ? "Autofix finished on the current local commit" : "Autofix changes committed locally"
            if metadata.pullRequestAutomation[key]?.hasRemoteSources == false,
               metadata.pullRequestAutomation[key]?.isLocalStage == false
            {
                metadata.pullRequestAutomation[key]?.isAutomatic = false
                metadata.pullRequestAutomation[key]?.loopResult = .finished
            }
        }
    }

    func markAddressed(_ attempt: AutofixAttempt, result: AutofixResult, context: AutofixContext) async throws -> Bool {
        let key = context.key
        let store = context.store
        let driver = context.driver
        try markLocalAddressed(attempt, result: result, context: context)
        guard result.addressedThreadIDs.subtracting(attempt.localThreadIDs).isEmpty == false else {
            return true
        }
        guard let state = store.load().pullRequestAutomation[key], state.attempt?.id == attempt.id,
              let fresh = try await driver.summary(state, true), state.matches(fresh),
              fresh.state == "OPEN", let markedHead = fresh.headCommit
        else {
            return false
        }

        let threads = try await driver.threads(state, true)
        guard try await driver.summary(state, true)?.headCommit == markedHead else {
            return false
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
                    head: markedHead == result.commit ? attempt.remoteHead : markedHead,
                    commentID: mark.commentID,
                    fixCommit: result.commit,
                )
            }
        }
        return true
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
                if let captured = metadata.pullRequestAutomation[key]?.collection?.review,
                   (captured.runID ?? captured.revision) == (review.runID ?? review.revision)
                {
                    metadata.pullRequestAutomation[key]?.collection?.review = review
                }
            }
        }
    }
}
