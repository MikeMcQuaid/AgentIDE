import AgentIDEDomain
import Foundation

actor AutofixCoordinator {
    var isRefreshing = false
    var lastReported: [String: PullRequestAutomation] = [:]

    func hasChanges(store: MetadataStore) -> Bool {
        let current = store.load().pullRequestAutomation
        defer { lastReported = current }
        return current != lastReported
    }

    func refresh(store: MetadataStore, driver: AutofixDriver) async {
        guard isRefreshing == false else {
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }
        for (key, state) in store.load().pullRequestAutomation where state.needsRefresh {
            do {
                try await reconcile(context: AutofixContext(key: key, store: store, driver: driver))
            } catch {
                store.update { value in
                    let running = value.pullRequestAutomation[key]?.isAutomatic == true
                    value.pullRequestAutomation[key]?.pending = running ? "Waiting for the next refresh" : ""
                    value.pullRequestAutomation[key]?.lastResult = error.localizedDescription
                }
            }
        }
    }

    func reconcile(context: AutofixContext) async throws {
        let key = context.key
        let store = context.store
        let driver = context.driver
        guard let state = store.load().pullRequestAutomation[key],
              let summary = try await driver.summary(state, false), state.matches(summary),
              let head = summary.headCommit
        else {
            store.update { $0.pullRequestAutomation[key]?.pending = "Waiting for the current PR head" }
            return
        }
        guard summary.state == "OPEN" else {
            store.update { value in
                value.pullRequestAutomation[key]?.pending = "Pull request is closed"
                value.pullRequestAutomation[key]?.isAutomatic = false
                value.pullRequestAutomation[key]?.pushedCommit = nil
                value.pullRequestAutomation[key]?.pushedFrom = nil
                value.pullRequestAutomation[key]?.attempt = nil
                value.pullRequestAutomation[key]?.resolutions = [:]
            }
            return
        }

        try await resolveMarked(state: state, head: head, context: context)
        guard try confirmPush(state, head: head, context: context) else {
            return
        }
        guard state.attempt != nil || state.canStartRound else {
            store.update { $0.pullRequestAutomation[key]?.pending = "" }
            return
        }
        guard let target = await driver.target(state, summary) else {
            store.update { $0.pullRequestAutomation[key]?.pending = "Waiting for this branch's running agent" }
            return
        }

        if let attempt = state.attempt {
            try await finish(attempt, summary: summary, target: target, context: context)
            return
        }
        try await gather(state, summary: summary, target: target, context: context)
    }

    func gather(
        _ state: PullRequestAutomation,
        summary: PullRequestSummary,
        target: AutofixDriver.Target,
        context: AutofixContext,
    ) async throws {
        let key = context.key
        let store = context.store
        let driver = context.driver
        guard let head = summary.headCommit else {
            return
        }
        guard [.done, .idle].contains(target.session.activity) else {
            store.update { $0.pullRequestAutomation[key]?.pending = "Waiting for the agent's current turn" }
            return
        }

        let localHead = await driver.head(target) ?? head
        guard state.isLocalStage || state.hasRemoteSources == false || localHead == head else {
            store.update { value in
                value.pullRequestAutomation[key]?.pending = "Push the current fixes before gathering remote feedback"
            }
            return
        }
        guard await driver.ready(target, localHead) else {
            store.update { $0.pullRequestAutomation[key]?.pending = "Waiting for the agent and the current head" }
            return
        }
        guard try await feedbackReady(state.stageSelection, summary: summary, target: target, context: context) else {
            return
        }
        guard let current = store.load().pullRequestAutomation[key] else {
            return
        }

        let candidate = try await candidate(
            state: current.stageSelection, summary: summary, head: localHead, fresh: false, driver: driver,
        )
        guard let candidate else {
            if current.isLocalStage {
                try await finishLocalStage(summary: summary, target: target, context: context)
                return
            }
            store.update { value in
                value.pullRequestAutomation[key]?.pending = ""
                value.pullRequestAutomation[key]?.isAutomatic = false
                value.pullRequestAutomation[key]?.lastResult = "Selected feedback is clear or already handled"
            }
            return
        }

        try await send(candidate, summary: summary, head: localHead, target: target, context: context)
    }

    func send(
        _ candidate: AutofixCandidate,
        summary: PullRequestSummary,
        head: String,
        target: AutofixDriver.Target,
        context: AutofixContext,
    ) async throws {
        let key = context.key
        let store = context.store
        let driver = context.driver
        guard let state = store.load().pullRequestAutomation[key] else {
            return
        }

        let prompt = try await driver.prepare(state, summary, candidate)
        guard let fresh = try await driver.summary(state, true), fresh.state == "OPEN", state.matches(fresh),
              fresh.headBranch == summary.headBranch, fresh.headCommit == summary.headCommit,
              let checked = try await self.candidate(
                  state: state.stageSelection, summary: fresh, head: head, fresh: true, driver: driver,
              ),
              checked == candidate, let paneID = target.session.paneID,
              try await driver.summary(state, true)?.headCommit == summary.headCommit,
              await driver.ready(target, head)
        else {
            store.update { $0.pullRequestAutomation[key]?.pending = "Waiting: head, permissions or feedback changed" }
            return
        }

        if state.isLocalStage {
            guard let collection = try await driver.collect(state, target, false),
                  collection.isPending == false, collection.failure == nil,
                  collection.id == state.collection?.id
            else {
                return
            }
        }
        let attempt = AutofixAttempt(
            id: UUID().uuidString,
            sources: candidate.sources,
            head: head,
            remoteHead: fresh.headCommit ?? head,
            localThreadIDs: candidate.localThreadIDs,
            branch: fresh.headBranch,
            worktreePath: target.worktree.path,
            sessionName: target.session.name,
            paneID: paneID,
            threads: candidate.threads,
        )
        guard try claim(attempt, events: candidate.events, settings: state, context: context) else {
            return
        }

        do {
            try await driver.deliver(attempt, prompt)
        } catch {
            store.update { value in
                value.pullRequestAutomation[key]?.lastResult = "Delivery unconfirmed; it will not be repeated. "
                    + error.localizedDescription
            }
        }
    }

    func claim(
        _ attempt: AutofixAttempt,
        events: Set<String>,
        settings: PullRequestAutomation,
        context: AutofixContext,
    ) throws -> Bool {
        let key = context.key
        let store = context.store
        var claimed = false
        try store.updatePersisting { metadata in
            guard var current = metadata.pullRequestAutomation[key], current.attempt == nil,
                  current.handledEvents.isDisjoint(with: events),
                  current.canStartRound, current.allows(attempt.sources),
                  current.selectedSources == settings.selectedSources,
                  current.botRequests == settings.botRequests,
                  current.reviewBot == settings.reviewBot,
                  current.isLocalStage == settings.isLocalStage,
                  attempt.sources.isSubset(of: current.stageSelection.selectedSources),
                  current.collection?.id == settings.collection?.id,
                  current.reviewer == settings.reviewer,
                  metadata.pullRequestAutomation.values.allSatisfy({ $0.attempt?.worktreePath != attempt.worktreePath })
            else {
                return
            }

            if current.isLocalStage {
                current.localRounds = current.localRounds ?? LocalAutofixRounds()
                current.localRounds?.started += 1
            } else {
                current.roundsStarted += 1
            }
            current.handledEvents.formUnion(events)
            current.attempt = attempt
            current.pending = "Autofix queued; waiting for the agent’s result"
            metadata.pullRequestAutomation[key] = current
            claimed = true
        }
        return claimed
    }
}
