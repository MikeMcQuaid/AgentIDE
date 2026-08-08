import AgentIDEDomain
import SwiftUI

/// The prompt-to-worktree entry point: pick a repository and agent,
/// type the problem statement and any extra agent arguments, go.
public struct NewSessionSheet: View {
    // MARK: Lifecycle

    /// Creates the sheet.
    public init(model: DashboardModel) {
        self.model = model
    }

    // MARK: Public

    /// The form.
    public var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            Text("New agent session").font(.title2)
            Picker("Repository", selection: $repository) {
                Text("Choose").tag(Repository?.none)
                ForEach(model.repositories) { repository in
                    Text(repository.name).tag(Repository?.some(repository))
                }
            }
            Picker("Agent", selection: $agent) {
                ForEach(AgentKind.allCases, id: \.self) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            TextField("Extra agent arguments (optional)", text: $arguments)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
            TextEditor(text: $prompt)
                .font(.body)
                .frame(minHeight: Self.promptHeight)
                .border(.separator)
            HStack {
                Spacer()
                Button("Cancel") { model.showsNewSession = false }
                Button("Start agent") { start() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(repository == nil || prompt.isEmpty)
            }
        }
        .padding()
        .frame(minWidth: Self.minimumWidth)
    }

    // MARK: Private

    private static let spacing: CGFloat = 12
    private static let promptHeight: CGFloat = 140
    private static let minimumWidth: CGFloat = 480

    @State private var repository: Repository?
    @State private var agent: AgentKind = .claudeCode
    @State private var prompt = ""
    @AppStorage("newSessionArguments")
    private var arguments = ""

    private let model: DashboardModel

    private func start() {
        guard let repository else {
            return
        }

        Task {
            await model.createSession(
                repository: repository,
                prompt: prompt,
                agent: agent,
                extraArguments: arguments,
            )
        }
    }
}
