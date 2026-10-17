import AgentIDEDomain

// MARK: - SetupStep

/// Prerequisites in the order the setup wizard presents them.
public enum SetupStep: Int, CaseIterable, Sendable {
    case tools = 1
    case gitIdentity = 2
    case github = 3
    case sandbox = 4
    case agent = 5
}

// MARK: - SetupIssue

/// A prerequisite the user must supply before the app can run.
public struct SetupIssue: Equatable, Sendable {
    public let step: SetupStep
    public let title: String
    public let explanation: String
    public let commands: String
    public let alternative: String
}

// MARK: - SetupResult

/// Local agent availability accompanies the prerequisite failures.
public struct SetupResult: Sendable {
    // MARK: Lifecycle

    /// Signing availability is independent of the prerequisites that block setup.
    init(issues: [SetupIssue], agents: [AgentKind], signingConfigured: Bool = true) {
        self.issues = issues
        self.agents = agents
        self.signingConfigured = signingConfigured
    }

    // MARK: Public

    public let issues: [SetupIssue]
    public let agents: [AgentKind]
    public let signingConfigured: Bool
}
