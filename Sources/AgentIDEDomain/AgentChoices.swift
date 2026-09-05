/// What an agent offers a session form, and what that form starts on.
///
/// The defaults matter as much as the lists: a picker that opens on
/// nothing makes the first thing anyone does a choice between names
/// they have to look up, and a form that refuses to start until they
/// have made it.
public struct AgentChoices: Hashable, Sendable {
    // MARK: Lifecycle

    /// Creates the choices.
    public init(
        models: [String],
        efforts: [String],
        defaultModel: String,
        defaultEffort: String,
        names: [String: String] = [:],
    ) {
        self.models = models
        self.efforts = efforts
        self.defaultModel = defaultModel
        self.defaultEffort = defaultEffort
        self.names = names
    }

    // MARK: Public

    /// The models the agent offers, as it named them.
    public let models: [String]

    /// Its reasoning tiers, strongest first.
    public let efforts: [String]

    /// The model a form opens on: the first the agent listed.
    public let defaultModel: String

    /// The effort it opens on, which is what the CLI itself would
    /// run at rather than the first of its tiers.
    public let defaultEffort: String

    /// Fuller names the agent itself reported, by model name: an
    /// alias like `fable` reads as the version it stands for where
    /// the agent has said which, and as itself where it has not.
    public let names: [String: String]
}
