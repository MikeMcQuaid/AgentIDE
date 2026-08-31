import AgentIDEData
import AgentIDEDomain
import AppIntents
import AppKit
import DashboardFeature
import TerminalUI

// MARK: - RepositoryEntity

/// A repository as Shortcuts and Siri see it, resolved from the
/// dashboard's in-memory groups so no git runs to answer.
struct RepositoryEntity: AppEntity {
    // MARK: Lifecycle

    /// Labelled by the path, not the id: a memberwise-looking init
    /// is one the formatter deletes, and the synthesised one wants
    /// the property wrapper's own type.
    init(path: String, name: String) {
        id = path
        self.name = name
    }

    // MARK: Internal

    static let typeDisplayRepresentation: TypeDisplayRepresentation = .init(name: "Repository")
    static let defaultQuery: RepositoryQuery = .init()

    /// The checkout path.
    let id: String

    /// Properties, not plain constants: that is what Shortcuts reads
    /// off an entity in later actions, and what the testing
    /// framework's lookups by name find.
    @Property(title: "Name")
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    var repository: Repository {
        Repository(name: name, path: id)
    }
}

// MARK: - RepositoryQuery

nonisolated struct RepositoryQuery: EntityStringQuery {
    // MARK: Internal

    @MainActor
    func entities(for identifiers: [String]) -> [RepositoryEntity] {
        Self.all().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func entities(matching string: String) -> [RepositoryEntity] {
        Self.all().filter { $0.name.localizedCaseInsensitiveContains(string) }
    }

    @MainActor
    func suggestedEntities() -> [RepositoryEntity] {
        Self.all()
    }

    // MARK: Private

    @MainActor
    private static func all() -> [RepositoryEntity] {
        (AppDependencies.shared?.dashboard.groups ?? [])
            .map { RepositoryEntity(path: $0.repository.path, name: $0.repository.name) }
    }
}

// MARK: - WorktreeEntity

/// A worktree row: repository, branch and what its agent is doing.
struct WorktreeEntity: AppEntity {
    // MARK: Lifecycle

    @MainActor
    init(_ item: WorktreeItem) {
        id = item.worktree.path
        repository = item.worktree.repositoryName
        branch = item.worktree.branch
        state = Self.state(of: item)
    }

    // MARK: Internal

    static let typeDisplayRepresentation: TypeDisplayRepresentation = .init(name: "Worktree")
    static let defaultQuery: WorktreeQuery = .init()

    /// The worktree path.
    let id: String

    @Property(title: "Repository")
    var repository: String

    @Property(title: "Branch")
    var branch: String

    @Property(title: "State")
    var state: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(repository): \(branch)", subtitle: "\(state)")
    }

    /// The sidebar's vocabulary in words.
    @MainActor
    static func state(of item: WorktreeItem) -> String {
        guard let session = item.session else {
            return "no agent"
        }
        guard session.status == .running else {
            return "agent exited"
        }

        return switch session.activity {
        case .working:
            "working"

        case .idle:
            "idle"

        case .done:
            item.hasUnread ? "done, unread" : "done"

        case .blocked:
            "waiting on input"

        case nil:
            "connected"
        }
    }
}

// MARK: - WorktreeQuery

nonisolated struct WorktreeQuery: EntityStringQuery {
    @MainActor
    static func all() -> [WorktreeEntity] {
        (AppDependencies.shared?.dashboard.groups ?? [])
            .flatMap(\.items)
            .filter { $0.isPlaceholder == false }
            .map(WorktreeEntity.init)
    }

    @MainActor
    static func item(at path: String) -> WorktreeItem? {
        (AppDependencies.shared?.dashboard.groups ?? [])
            .flatMap(\.items)
            .first { $0.worktree.path == path }
    }

    @MainActor
    func entities(for identifiers: [String]) -> [WorktreeEntity] {
        Self.all().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func entities(matching string: String) -> [WorktreeEntity] {
        Self.all().filter { entity in
            entity.branch.localizedCaseInsensitiveContains(string)
                || entity.repository.localizedCaseInsensitiveContains(string)
        }
    }

    @MainActor
    func suggestedEntities() -> [WorktreeEntity] {
        Self.all()
    }
}

// MARK: - AgentChoice

nonisolated enum AgentChoice: String, AppEnum {
    // The case names are the values Shortcuts store (SwiftFormat
    // strips explicit raw values): keep them stable.
    // swiftlint:disable explicit_enum_raw_value
    case claude
    case codex
    // swiftlint:enable explicit_enum_raw_value

    // MARK: Internal

    static let typeDisplayRepresentation: TypeDisplayRepresentation = .init(name: "Agent")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .claude: "Claude Code",
        .codex: "Codex",
    ]

    var kind: AgentKind {
        switch self {
        case .claude:
            .claudeCode

        case .codex:
            .codexCLI
        }
    }
}

// MARK: - StartSessionIntent

// periphery:ignore - the system finds intents by conformance
/// The same funnel `agentide new` and the form use, from a Shortcut
/// or Siri: a Shortcut on a phone starts work on the Mac with no SSH.
struct StartSessionIntent: AppIntent {
    // MARK: Internal

    static let title: LocalizedStringResource = "Start Agent Session"
    static let description: IntentDescription = .init("Makes a worktree and starts an agent on a prompt.")
    static let openAppWhenRun = true

    static var parameterSummary: some ParameterSummary {
        Summary("Start \(\.$agent) on \(\.$repository) with \(\.$prompt)")
    }

    @Parameter(title: "Repository")
    var repository: RepositoryEntity

    @Parameter(title: "Prompt")
    var prompt: String

    @Parameter(title: "Agent", default: .claude)
    var agent: AgentChoice

    @MainActor
    func perform() async -> some IntentResult & ProvidesDialog {
        guard let dependencies = AppDependencies.shared else {
            return .result(dialog: "AgentIDE is still starting; try again in a moment.")
        }

        // The model and effort last chosen anywhere, the form's own
        // defaults; nil leaves the agent to its own.
        let defaults = UserDefaults.standard
        let options = AgentLaunchOptions(
            model: Self.nonEmpty(defaults.string(forKey: "agentModel")),
            effort: Self.nonEmpty(defaults.string(forKey: "agentEffort")),
        )
        await dependencies.dashboard.createSession(
            repository: repository.repository,
            prompt: prompt,
            agent: agent.kind,
            options: options,
        )
        return .result(dialog: "Started \(agent.kind.displayName) on \(repository.name).")
    }

    // MARK: Private

    private static func nonEmpty(_ value: String?) -> String? {
        value.flatMap { $0.isEmpty ? nil : $0 }
    }
}

// MARK: - ShowWorktreeIntent

// periphery:ignore - the system finds intents by conformance
struct ShowWorktreeIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Worktree"
    static let description: IntentDescription = .init("Selects a worktree and brings the window forward.")
    static let openAppWhenRun = true

    static var parameterSummary: some ParameterSummary {
        Summary("Show \(\.$worktree)")
    }

    @Parameter(title: "Worktree")
    var worktree: WorktreeEntity

    @MainActor
    func perform() -> some IntentResult & ProvidesDialog {
        guard let dependencies = AppDependencies.shared,
              let item = WorktreeQuery.item(at: worktree.id)
        else {
            return .result(dialog: "That worktree is not in the sidebar any more.")
        }

        dependencies.dashboard.select(item)
        NSApp.activate()
        return .result(dialog: "Showing \(worktree.repository): \(worktree.branch).")
    }
}

// MARK: - OpenPullRequestsIntent

// periphery:ignore - the system finds intents by conformance
struct OpenPullRequestsIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Pull Requests"
    static let description: IntentDescription = .init("Shows a worktree's pull request tab.")
    static let openAppWhenRun = true

    static var parameterSummary: some ParameterSummary {
        Summary("Open pull requests for \(\.$worktree)")
    }

    @Parameter(title: "Worktree")
    var worktree: WorktreeEntity

    @MainActor
    func perform() -> some IntentResult & ProvidesDialog {
        guard let dependencies = AppDependencies.shared,
              let item = WorktreeQuery.item(at: worktree.id)
        else {
            return .result(dialog: "That worktree is not in the sidebar any more.")
        }

        dependencies.dashboard.select(item)
        // The storage bus every tab switch travels on.
        UserDefaults.standard.set(UtilityTab.pullRequests.rawValue, forKey: UtilityTabTarget.key)
        UserDefaults.standard.set(true, forKey: UtilityTabTarget.visibilityKey)
        NSApp.activate()
        return .result(dialog: "Pull requests for \(worktree.branch).")
    }
}

// MARK: - WhatNeedsMeIntent

// periphery:ignore - the system finds intents by conformance
/// Answered without stealing focus: the worktrees waiting on input
/// or holding an unread finished turn, spoken and returned.
nonisolated struct WhatNeedsMeIntent: AppIntent {
    static let title: LocalizedStringResource = "What Needs Me"
    static let description: IntentDescription = .init("Lists the agents waiting on you: blocked, or done and unread.")
    static let openAppWhenRun = false

    @MainActor
    func perform() -> some IntentResult & ReturnsValue<[WorktreeEntity]> & ProvidesDialog {
        let needing = (AppDependencies.shared?.dashboard.groups ?? [])
            .flatMap(\.items)
            .filter { $0.session?.activity == .blocked || $0.hasActionableUnread }
            .map(WorktreeEntity.init)
        guard needing.isEmpty == false else {
            return .result(value: [], dialog: "Nothing needs you.")
        }

        let spoken = needing.lazy.map { $0.repository + " " + $0.branch + ", " + $0.state }.joined(separator: "; ")
        return .result(value: needing, dialog: "\(needing.count) need you: \(spoken).")
    }
}

// MARK: - AgentIDEShortcuts

// periphery:ignore - the system finds the provider by conformance
nonisolated struct AgentIDEShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WhatNeedsMeIntent(),
            phrases: [
                "What needs me in \(.applicationName)",
                "Which agents are waiting in \(.applicationName)",
            ],
            shortTitle: "What Needs Me",
            systemImageName: "questionmark.circle",
        )
        AppShortcut(
            intent: StartSessionIntent(),
            phrases: ["Start an agent in \(.applicationName)"],
            shortTitle: "Start Agent Session",
            systemImageName: "play.circle",
        )
    }
}
