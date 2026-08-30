import AgentIDEDomain

/// Agent state as events. herdr's `agent wait` answers the moment a
/// pane's agent changes state, where the poll noticed within its
/// interval; one waiter per running agent turns a change into a
/// refresh at once, and the poll stays for git and as the safety
/// net. Each waiter is one herdr process alive for at most a few
/// minutes, far fewer than the snapshots a faster poll would cost.
extension DashboardModel {
    /// How long one wait lasts before it is simply asked again.
    static let agentWaitMilliseconds = 300_000

    /// Starts a waiter for every running agent that has none and
    /// stops those whose pane has gone.
    func watchAgentStates(_ groups: [RepositoryGroup]) {
        var live = [String: AgentSession]()
        for item in groups.flatMap(\.items) {
            if let session = item.session, session.status == .running, let paneID = session.paneID {
                live[paneID] = session
            }
        }
        for (paneID, task) in agentWatchers where live[paneID] == nil {
            task.cancel()
            agentWatchers[paneID] = nil
        }
        for (paneID, session) in live where agentWatchers[paneID] == nil {
            agentWatchers[paneID] = Task { [weak self] in
                await self?.follow(session)
            }
        }
    }

    /// Waits on one agent for as long as it runs, refreshing on
    /// every change; the refresh re-reads the session, which is what
    /// the next wait starts from.
    private func follow(_ session: AgentSession) async {
        var current = session
        while Task.isCancelled == false {
            let changed = await service.waitForAgentChange(
                session: current,
                timeoutMilliseconds: Self.agentWaitMilliseconds,
            )
            guard Task.isCancelled == false else {
                return
            }

            if changed {
                await refresh()
            }
            guard let latest = groups.flatMap(\.items)
                .first(where: { $0.session?.paneID == current.paneID })?
                .session,
                latest.status == .running
            else {
                return
            }

            current = latest
        }
    }
}
