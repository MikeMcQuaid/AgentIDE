import AgentIDEDomain
import SwiftUI
import TerminalUI

/// The session entry point: pick a repository, then the shared form
/// starts from a typed prompt, an open issue or an open pull request.
/// Drafts survive quitting the app.
public struct NewSessionSheet: View {
    // MARK: Lifecycle

    /// Creates the sheet.
    public init(model: DashboardModel) {
        self.model = model
        _repository = State(initialValue: model.newSessionRepository)
    }

    // MARK: Public

    /// The repository picker over the shared form.
    public var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            HStack {
                Text("New agent session").font(.title2)
                Spacer()
                Button("Cancel") { model.showsNewSession = false }
                    .keyboardShortcut(.cancelAction)
                    .hoverHelp("Close without starting anything")
            }
            Picker("Repository", selection: $repository) {
                Text("Choose repository").tag(Repository?.none)
                ForEach(model.repositories) { repository in
                    Text(repository.fullName ?? repository.name).tag(Repository?.some(repository))
                }
            }
            .labelsHidden()
            .hoverHelp("The repository the worktree is created in; issues and pull requests load from it")
            AgentSessionForm(
                model: model,
                repository: repository,
                submitTitle: "Start agent",
                submitHelp: "Create a worktree and branch and launch the agent in it",
            ) { submission in await start(submission) }
        }
        .padding()
        .frame(minWidth: Self.minimumWidth)
        // Sheet state persists across presentations, so the init's
        // seed only applies the first time; re-read the preset on
        // every appearance or a repository plus would show the
        // previous pick.
        .onAppear {
            if let preset = model.newSessionRepository {
                repository = preset
            }
        }
    }

    // MARK: Private

    private static let spacing: CGFloat = 10
    private static let minimumWidth: CGFloat = 520

    @State private var repository: Repository?

    private let model: DashboardModel

    private func start(_ submission: AgentSessionForm.Submission) async {
        guard let repository else {
            return
        }

        switch submission.source {
        case .prompt:
            await model.createSession(
                repository: repository,
                prompt: submission.prompt,
                agent: submission.agent,
                options: submission.options,
            )

        case .issue:
            guard let number = submission.number else {
                return
            }

            await model.createSession(
                fromIssue: number,
                repository: repository,
                context: submission.context,
                agent: submission.agent,
                options: submission.options,
            )

        case .pullRequest:
            guard let number = submission.number else {
                return
            }

            await model.createSession(
                fromPullRequest: number,
                repository: repository,
                context: submission.context,
                agent: submission.agent,
                options: submission.options,
            )
        }
    }
}
