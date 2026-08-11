import AgentIDEDomain
import SwiftUI

/// Starts an agent in a worktree that has none, using the same form
/// as the New Session sheet with the repository fixed. Issue picks
/// run in this worktree; pull request picks check out their own.
public struct CreateSessionPane: View {
    // MARK: Lifecycle

    /// Creates the pane; `onStarted` runs after a successful launch.
    @preconcurrency
    public init(worktree: Worktree, model: DashboardModel, onStarted: @escaping @MainActor () async -> Void) {
        self.worktree = worktree
        self.model = model
        self.onStarted = onStarted
    }

    // MARK: Public

    /// The shared form, targeted at this worktree, hugging the
    /// pane's top like the repository page.
    public var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            Text("Start an agent in \(target)")
                .font(.subheadline.weight(.semibold))
                .padding(.top, Self.headerTopPadding)
            AgentSessionForm(
                model: model,
                repository: repository,
                submitTitle: "Start agent",
                submitHelp: "Launch the agent in this worktree; a pull request pick checks out its own worktree",
            ) { submission in await start(submission) }
            Spacer()
        }
        .padding([.horizontal, .bottom], Self.spacing)
    }

    // MARK: Private

    private static let spacing: CGFloat = 8
    private static let headerTopPadding: CGFloat = 3

    private let worktree: Worktree
    private let model: DashboardModel
    private let onStarted: @MainActor () async -> Void

    private var repository: Repository {
        Repository(name: worktree.repositoryName, path: worktree.repositoryPath)
    }

    private var target: String {
        worktree.repositoryName + ": " + worktree.branch
    }

    private func start(_ submission: AgentSessionForm.Submission) async {
        switch submission.source {
        case .prompt:
            await model.launchAgent(
                in: worktree,
                prompt: submission.prompt,
                agent: submission.agent,
                options: submission.options,
            )

        case .issue:
            guard let number = submission.number else {
                return
            }

            await model.launchAgent(
                fromIssue: number,
                in: worktree,
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
        await onStarted()
    }
}
