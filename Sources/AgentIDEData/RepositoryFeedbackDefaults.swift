import AgentIDEDomain

/// The reviewer for new feedback contexts, without automation opt-ins.
public struct RepositoryFeedbackDefaults: Codable, Equatable, Sendable {
    public var reviewer: AgentKind?
    public var reviewBot: ReviewBot?
}
