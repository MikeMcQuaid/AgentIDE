import AgentIDEDomain
import SwiftUI

/// Starts an agent in a worktree that has none, using the same form
/// as the New Session sheet with the repository fixed. Issue picks
/// run in this worktree; pull request picks check out their own.
public struct CreateSessionPane: View {
    // MARK: Lifecycle

    /// Creates the pane; `canResume` offers `onResume` for the
    /// worktree's most recent conversation, `onStarted` runs after a
    /// successful launch, `onShowConversations`, when given, goes
    /// back to the list this form was reached from and
    /// `onOpenEditor` offers the centre editor in this pane's place.
    @preconcurrency
    public init(
        worktree: Worktree,
        model: DashboardModel,
        canResume: Bool,
        onShowConversations: (@MainActor @Sendable () -> Void)? = nil,
        onOpenEditor: (@MainActor @Sendable () -> Void)? = nil,
        onResume: @escaping @MainActor () async -> Void,
        onStarted: @escaping @MainActor () async -> Void,
    ) {
        self.onShowConversations = onShowConversations
        self.onOpenEditor = onOpenEditor
        self.worktree = worktree
        self.model = model
        self.canResume = canResume
        self.onResume = onResume
        self.onStarted = onStarted
    }

    // MARK: Public

    /// The shared form, targeted at this worktree, hugging the
    /// pane's top like the repository page.
    public var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            HStack {
                Text("Start an agent in \(target)")
                    .font(.subheadline.weight(.semibold))
                if isResuming {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                if let onOpenEditor {
                    Button("Editor", action: onOpenEditor)
                        .controlSize(.small)
                        .hoverHelp("Edit this worktree's files in this pane without starting an agent")
                }
                if let onShowConversations {
                    Button("Conversations", action: onShowConversations)
                        .controlSize(.small)
                        .hoverHelp("Back to this worktree's past conversations")
                }
                if canResume {
                    Button("Resume last session") { resume() }
                        .controlSize(.small)
                        .disabled(isResuming)
                        .hoverHelp("Continue this worktree's most recent conversation instead of starting fresh")
                }
            }
            .padding(.top, Self.headerTopPadding)
            AgentSessionForm(
                model: model,
                repository: repository,
                submitTitle: "Start agent",
                submitHelp: "Launch the agent in this worktree (Cmd-Return); "
                    + "a pull request pick checks out its own worktree",
            ) { submission in await start(submission) }
            Spacer()
        }
        .padding([.horizontal, .bottom], Self.spacing)
    }

    // MARK: Private

    private static let spacing: CGFloat = 8
    private static let headerTopPadding: CGFloat = 3

    /// Instant feedback while a resume launches.
    @State private var isResuming = false

    private let onShowConversations: (@MainActor @Sendable () -> Void)?
    private let onOpenEditor: (@MainActor @Sendable () -> Void)?
    private let worktree: Worktree
    private let model: DashboardModel
    private let canResume: Bool
    private let onResume: @MainActor () async -> Void
    private let onStarted: @MainActor () async -> Void

    private var repository: Repository {
        Repository(name: worktree.repositoryName, path: worktree.repositoryPath)
    }

    private var target: String {
        worktree.repositoryName + ": " + worktree.branch
    }

    private func resume() {
        isResuming = true
        Task {
            await onResume()
            isResuming = false
        }
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
