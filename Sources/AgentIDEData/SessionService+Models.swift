import AgentIDEDomain
import Foundation

/// What models an agent offers: its own listing where it has one,
/// and nothing to ask where it has none. Split from the sources for
/// length.
public extension SessionService {
    // nil means "keep the fallback list", which callers treat
    // differently from an empty answer.
    // swiftlint:disable discouraged_optional_collection

    /// Asks the agent's CLI for its current models; nil when the
    /// command fails or yields nothing. The CLI runs inside the
    /// sandbox, where sessions run it anyway; running it as the host
    /// user made macOS prompt for broad disk access.
    func discoverModels(for agent: AgentKind) async -> [String]? {
        // swiftlint:enable discouraged_optional_collection
        let runner = runner(for: agent)
        if runner.modelListingCommand.isEmpty {
            forgetDiscoveredModels(for: agent)
        }
        // An agent with no listing command has a curated list and
        // nothing to discover; asking anyway starts a session.
        guard runner.modelListingCommand.isEmpty == false else {
            return nil
        }

        let argv = launcher.command(
            payload: runner.modelListingCommand.joined(separator: " ") + " </dev/null",
            initialDirectory: launcher.sharedWorkspace,
            sessionID: UUID().uuidString,
            sessionName: "agentide-model-listing",
        )
        let result = try? await processes.run(argv, workingDirectory: nil, environment: [:])
        guard let result, result.succeeded else {
            return nil
        }

        let models = runner.parseModelList(result.standardOutput)
        return models.isEmpty ? nil : models
    }

    /// Throws away what was once discovered for an agent, so a list
    /// scraped before the app knew better stops being offered.
    func forgetDiscoveredModels(for agent: AgentKind) {
        store.update { metadata in
            metadata.discoveredModels[agent.rawValue] = nil
            metadata.discoveredModelsVersion[agent.rawValue] = nil
        }
    }

    /// Whether an agent has a listing of its own at all; one that
    /// does not is offered its curated models and nothing else.
    func reportsModels(_ agent: AgentKind) -> Bool {
        runner(for: agent).modelListingCommand.isEmpty == false
    }
}
