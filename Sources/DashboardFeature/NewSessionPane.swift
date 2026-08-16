import AgentIDEDomain
import SwiftUI
import TerminalUI

/// The session entry point, shown in the middle pane rather than a
/// sheet: pick a repository, then the shared form starts from a
/// typed prompt, an open issue or an open pull request. Drafts
/// survive quitting the app.
public struct NewSessionPane: View {
    // MARK: Lifecycle

    /// Creates the pane.
    public init(model: DashboardModel) {
        self.model = model
        _repository = State(initialValue: model.newSessionRepository)
    }

    // MARK: Public

    /// The repository picker over the shared form, hugging the
    /// pane's top like the other middle-pane pages.
    public var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            // No cancel button: any other middle-pane action, like
            // selecting a worktree, replaces this page.
            Text("New agent session").font(.subheadline.weight(.semibold))
            Picker("Repository", selection: $repository) {
                Text("Choose repository").tag(Repository?.none)
                ForEach(model.repositories) { repository in
                    Text(repository.fullName ?? repository.name).tag(Repository?.some(repository))
                }
            }
            .labelsHidden()
            // A preset repository is the whole point of the opener
            // that set it, so it cannot be changed here.
            .disabled(model.newSessionRepository != nil)
            .hoverHelp(
                model.newSessionRepository == nil
                    ? "The repository the worktree is created in; issues and pull requests load from it"
                    : "Fixed by where you opened this from",
            )
            AgentSessionForm(
                model: model,
                repository: repository,
                submitTitle: "Start agent",
                submitHelp: "Create a worktree and branch and launch the agent in it (Cmd-Return)",
            ) { submission in await start(submission) }
            if let failure = model.screenError {
                Text(failure)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
            Spacer()
        }
        .padding([.horizontal, .bottom])
        .padding(.top, Self.topPadding)
        .frame(maxWidth: Self.maximumWidth, maxHeight: .infinity, alignment: .top)
        // View state persists across presentations, so the init's
        // seed only applies the first time; re-read the preset on
        // every appearance or a repository plus would show the
        // previous pick.
        .onAppear { repository = resolvedPreset ?? repository }
    }

    // MARK: Private

    private static let spacing: CGFloat = 10
    private static let topPadding: CGFloat = 3
    private static let maximumWidth: CGFloat = 640

    @State private var repository: Repository?

    private let model: DashboardModel

    /// The preset re-resolved against the picker's own list: the
    /// sidebar's copy differs (its full name comes from GitHub), and
    /// the picker only shows a selection it contains an equal of.
    private var resolvedPreset: Repository? {
        guard let preset = model.newSessionRepository else {
            return nil
        }

        return model.repositories.first { $0.path == preset.path } ?? preset
    }

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
