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

    /// What identifies the answer a listing would give: the CLI's
    /// own version, and where the list comes from a cache the server
    /// rewrites, that file's modification time as well. Keyed on the
    /// version alone, a model added server-side stayed missing from
    /// the picker until the CLI itself was upgraded.
    func modelListingStamp(for agent: AgentKind) async -> String? {
        let version = await probeVersion(of: agent)
        guard let file = runner(for: agent).modelCacheFile else {
            return version
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: paths.sandboxHome + "/" + file)
        let modified = attributes?[.modificationDate] as? Date
        return (version ?? "") + "#" + (modified?.timeIntervalSince1970.description ?? "")
    }

    /// The fuller names an agent reports for its own models, by the
    /// name `--model` takes. Read from the file the agent keeps
    /// rather than written here, so a new version names itself the
    /// first time it is used.
    func modelNames(for agent: AgentKind) -> [String: String] {
        guard let file = runner(for: agent).modelNamesFile,
              let data = FileManager.default.contents(atPath: paths.sandboxHome + "/" + file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }

        return ClaudeModelNames.names(fromIdentifiers: Self.modelIdentifiers(inClaudeState: json))
    }

    /// Every model identifier Claude Code's state names: the options
    /// it was offered, and the usage it recorded per project.
    static func modelIdentifiers(inClaudeState json: [String: Any]) -> [String] {
        var identifiers = [String]()
        let offered = json["additionalModelOptionsCache"] as? [[String: Any]] ?? []
        identifiers += offered.compactMap { $0["value"] as? String }
        let projects = json["projects"] as? [String: Any] ?? [:]
        for project in projects.values {
            let usage = (project as? [String: Any])?["lastModelUsage"] as? [String: Any] ?? [:]
            identifiers += usage.keys
        }
        return identifiers
    }

    /// What a picker starts on for an agent: the first model it
    /// offers and the effort the CLI itself would use. A form that
    /// opens on nothing makes the first thing anyone does a choice
    /// between names they have to look up.
    func launchDefaults(for agent: AgentKind, models: [String]) -> (model: String, effort: String) {
        let runner = runner(for: agent)
        return (models.first ?? runner.models.first ?? "", runner.defaultEffort ?? runner.efforts.first ?? "")
    }

    /// Whether an agent has a listing of its own at all; one that
    /// does not is offered its curated models and nothing else.
    func reportsModels(_ agent: AgentKind) -> Bool {
        runner(for: agent).modelListingCommand.isEmpty == false
    }
}
