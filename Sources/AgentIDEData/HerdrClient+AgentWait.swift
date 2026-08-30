import AgentIDEDomain

/// Waiting on herdr's agent detection, split from the sessions file
/// for length.
extension HerdrClient {
    /// Waits until a pane's agent leaves the state it is in, or the
    /// timeout passes: one waiter per running agent is what turns
    /// state changes into events the poll only ever noticed within
    /// its interval. True means the state changed.
    func waitForAgentChange(paneID: String, from activity: AgentActivity?, timeoutMilliseconds: Int) async -> Bool {
        let others = Self.agentStateNames.filter { $0 != activity.map(Self.name(of:)) }
        let result = try? await herdr(
            ["agent", "wait", paneID] + others.flatMap { ["--until", $0] }
                + ["--timeout", String(timeoutMilliseconds)],
            allowFailure: true,
        )
        return result?.succeeded == true
    }

    /// herdr's names for the states it detects, in its own order.
    private static let agentStateNames = ["working", "idle", "blocked", "done"]

    private static func name(of activity: AgentActivity) -> String {
        switch activity {
        case .working:
            "working"

        case .idle:
            "idle"

        case .blocked:
            "blocked"

        case .done:
            "done"
        }
    }
}
