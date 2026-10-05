import AgentIDEDomain
import SwiftUI
import TerminalUI

/// Repository schedules in Settings, remembering the selected repository.
public struct ScheduledPromptsView: View {
    // MARK: Lifecycle

    public init(model: ScheduledPromptsModel, dashboard: DashboardModel) {
        self.model = model
        self.dashboard = dashboard
    }

    // MARK: Public

    public var body: some View {
        VStack(alignment: .leading) {
            header
            Text("Runs while AgentIDE is open. Reopening or waking runs each overdue prompt once.")
                .interfaceFont(.caption)
                .foregroundStyle(.secondary)
            if let error = model.error {
                Text(error).foregroundStyle(.red).textSelection(.enabled)
            }
            ScrollView {
                LazyVStack(alignment: .leading) {
                    ForEach(repositoryPrompts) { prompt in
                        row(prompt)
                        Divider()
                    }
                }
            }
            .overlay {
                if repositoryPrompts.isEmpty {
                    ContentUnavailableView(
                        "No scheduled prompts",
                        systemImage: "calendar",
                        description: Text("Choose a repository and add a prompt to run regularly."),
                    )
                }
            }
        }
        .padding()
        .frame(minHeight: Self.height)
        .onAppear {
            if repositoryPath.isEmpty {
                repositoryPath = repositoryPaths.first ?? ""
            }
        }
        .sheet(item: $editing) { prompt in
            ScheduledPromptEditor(prompt: prompt, model: model, choices: dashboard.launchChoices)
        }
    }

    // MARK: Private

    private static let previewLines = 2
    private static let height: CGFloat = 480

    @AppStorage("scheduledRepositoryPath")
    private var repositoryPath = ""
    @State private var editing: ScheduledPrompt?

    private let model: ScheduledPromptsModel
    private let dashboard: DashboardModel

    private var repositoryPaths: [String] {
        Set(dashboard.groups.map(\.repository.path) + model.prompts.map(\.repositoryPath)
            + (repositoryPath.isEmpty ? [] : [repositoryPath])).sorted()
    }

    private var repositoryPrompts: [ScheduledPrompt] {
        model.prompts
            .filter { $0.repositoryPath == repositoryPath }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var header: some View {
        HStack {
            Picker("Repository", selection: $repositoryPath) {
                if repositoryPath.isEmpty {
                    Text("Choose a repository").tag("")
                }
                ForEach(repositoryPaths, id: \.self) { path in
                    Text(URL(filePath: path).lastPathComponent).tag(path)
                }
            }
            Spacer()
            Button("Add scheduled prompt", systemImage: "plus") {
                var prompt = ScheduledPrompt(repositoryPath: repositoryPath)
                prompt.agent = AgentKind(rawValue: UserDefaults.standard.string(forKey: "agentKind") ?? "")
                    ?? .claudeCode
                editing = prompt
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .disabled(repositoryPath.isEmpty)
            .hoverHelp("Schedule a new prompt in this repository")
        }
    }

    private func row(_ prompt: ScheduledPrompt) -> some View {
        HStack {
            Toggle("Enable “" + prompt.name + "”", isOn: Binding(
                get: { prompt.isEnabled },
                set: { enabled in
                    var updated = prompt
                    updated.isEnabled = enabled
                    model.save(updated)
                },
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            details(prompt)
            Spacer()
            Button("Edit scheduled prompt", systemImage: "pencil") { editing = prompt }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .hoverHelp("Edit this prompt and its schedule")
            Button("Delete scheduled prompt", systemImage: "trash", role: .destructive) { model.delete(prompt) }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .disabled(model.runningID == prompt.id)
                .hoverHelp("Remove this schedule; existing sessions and worktrees are kept")
        }
        .padding(.vertical)
    }

    private func details(_ prompt: ScheduledPrompt) -> some View {
        VStack(alignment: .leading) {
            Text(prompt.name).interfaceFont(.headline)
            Text(prompt.prompt).lineLimit(Self.previewLines).foregroundStyle(.secondary)
            Text(prompt.schedule.frequency.rawValue.capitalized + " · " + prompt.agent.displayName)
                .interfaceFont(.caption)
            if model.runningID == prompt.id {
                Label("Starting agent…", systemImage: "hourglass")
            } else if let error = prompt.lastError {
                Text(error).foregroundStyle(.red).textSelection(.enabled)
            } else if let last = prompt.lastRun {
                Text("Last started: " + last.formatted(date: .abbreviated, time: .shortened))
                    .interfaceFont(.caption)
                    .hoverHelp(prompt.lastSession ?? "")
            }
            if prompt.isEnabled, let next = prompt.nextRun {
                Text("Next: " + next.formatted(date: .abbreviated, time: .shortened))
                    .interfaceFont(.caption)
            } else {
                Text("Paused").interfaceFont(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
