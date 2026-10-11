import AgentIDEDomain
import Foundation

extension AutofixCoordinator {
    func performPush(
        _ attempt: AutofixAttempt,
        commit: String,
        summary: PullRequestSummary,
        target: AutofixDriver.Target,
        context: AutofixContext,
    ) async throws {
        do {
            let pushed = try await context.driver.push(target, summary, commit)
            try complete(
                key: context.key,
                message: "Autofix pushed; waiting for GitHub confirmation",
                store: context.store,
                pushedCommit: pushed,
                previousHead: attempt.remoteHead,
            )
        } catch {
            try recordPushFailure(attempt, commit: commit, error: error, context: context)
        }
    }

    func recordPushFailure(
        _ attempt: AutofixAttempt, commit: String, error: any Error, context: AutofixContext,
    ) throws {
        try context.store.updatePersisting { metadata in
            guard var state = metadata.pullRequestAutomation[context.key], state.attempt?.id == attempt.id else {
                return
            }

            state.failedPush = FailedAutofixPush(
                id: UUID(),
                message: error.localizedDescription,
                attempt: attempt,
                commit: (error as? AutofixPushError)?.commit ?? commit,
            )
            state.attempt = nil
            state.isAutomatic = false
            state.loopResult = .failed
            state.pending = ""
            state.lastResult = "Automatic push failed. Choose Push to retry. " + error.localizedDescription
            metadata.pullRequestAutomation[context.key] = state
        }
    }

    func retryPush(_ failure: FailedAutofixPush, context: AutofixContext) async throws {
        let store = context.store
        let key = context.key
        let driver = context.driver
        guard let state = store.load().pullRequestAutomation[key], state.failedPush == failure,
              let fresh = try await driver.summary(state, failure.retryRequested), state.matches(fresh),
              fresh.headBranch == failure.attempt.branch, let remoteHead = fresh.headCommit
        else {
            return
        }

        if fresh.state == "OPEN" {
            try await resolveMarked(state: state, head: remoteHead, context: context)
        }
        if fresh.state != "OPEN" || remoteHead != failure.attempt.remoteHead {
            guard try await driver.summary(state, true)?.headCommit == remoteHead else {
                return
            }

            try confirmRetriedPush(failure, isOpen: fresh.state == "OPEN", context: context)
            return
        }
        guard failure.retryRequested else {
            return
        }
        guard var target = await driver.target(state, fresh),
              target.worktree.path == failure.attempt.worktreePath,
              target.worktree.branch == failure.attempt.branch,
              target.session.name == failure.attempt.sessionName, target.session.paneID == failure.attempt.paneID
        else {
            store.update { $0.pullRequestAutomation[key]?.pending = "Waiting for the original agent session" }
            return
        }

        target.allowsUncommitted = false
        guard [.done, .idle].contains(target.session.activity),
              let commit = try await currentCommit(replacing: failure.commit, target: target, context: context),
              await ready(target, head: commit, context: context),
              try resumePush(failure, context: context)
        else {
            return
        }

        try await push(
            failure.attemptWithUnclaimedPush,
            result: AutofixResult(
                attemptID: failure.attempt.id,
                head: failure.attempt.head,
                commit: commit,
                addressedThreadIDs: [],
            ),
            summary: fresh,
            target: target,
            context: context,
        )
    }

    private func confirmRetriedPush(
        _ failure: FailedAutofixPush, isOpen: Bool, context: AutofixContext,
    ) throws {
        try context.store.updatePersisting { metadata in
            guard metadata.pullRequestAutomation[context.key]?.failedPush == failure else {
                return
            }

            metadata.pullRequestAutomation[context.key]?.failedPush = nil
            metadata.pullRequestAutomation[context.key]?.localRounds?.lastAttempt = nil
            metadata.pullRequestAutomation[context.key]?.localRounds?.commit = nil
            metadata.pullRequestAutomation[context.key]?.isAutomatic = isOpen
            metadata.pullRequestAutomation[context.key]?.loopResult = nil
            metadata.pullRequestAutomation[context.key]?.pending = ""
            metadata.pullRequestAutomation[context.key]?.lastResult = isOpen
                ? "Manual push confirmed by GitHub; continuing feedback" : "Pull request is closed"
            if isOpen == false {
                metadata.pullRequestAutomation[context.key]?.resolutions = [:]
            }
        }
    }

    private func resumePush(_ failure: FailedAutofixPush, context: AutofixContext) throws -> Bool {
        var resumed = false
        try context.store.updatePersisting { metadata in
            guard var state = metadata.pullRequestAutomation[context.key], state.failedPush == failure,
                  state.pushAutomatically, state.localWorktreePath == nil, state.attempt == nil
            else {
                return
            }

            state.isAutomatic = true
            guard state.allows(failure.attempt.sources) else {
                return
            }

            state.failedPush = nil
            state.loopResult = nil
            state.attempt = failure.attemptWithUnclaimedPush
            metadata.pullRequestAutomation[context.key] = state
            resumed = true
        }
        return resumed
    }
}
