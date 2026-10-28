import SanductorData
import SanductorDomain
import SwiftUI
import TerminalUI

// MARK: - LaunchDraft

/// What a launch was asked to do, as its form would show it again.
struct LaunchDraft: Equatable {
    let text: String
    let source: AgentSessionForm.PromptSource
    let agent: AgentKind
    let options: AgentLaunchOptions
    var number: Int?
    var ghsaID: String?
    var base: String?
}

// MARK: - LaunchRetry

/// A draft on its way to a form: a failed launch's back to the one
/// that started it, the new session form or a worktree's own at
/// `worktreePath`, or a pull request list's to the new session form.
/// The repository matters too: a new session form still showing
/// another repository takes the draft only once it has switched,
/// since switching resets the picks.
struct LaunchRetry: Equatable {
    let repositoryPath: String
    let worktreePath: String?
    let draft: LaunchDraft
}

// MARK: - LaunchFailure

/// A launch that failed, kept on the row it was for so the error
/// stays beside that work rather than taking over whatever the
/// window shows by the time it fails.
public struct LaunchFailure: Equatable, Sendable {
    // MARK: Public

    public let message: String

    // MARK: Internal

    /// What Edit and retry puts back in the form.
    let draft: LaunchDraft
}

// MARK: - LaunchFailureView

/// A failed launch in its row's pane: what went wrong, then the way
/// back to the form with what was typed, or away from it.
public struct LaunchFailureView: View {
    // MARK: Lifecycle

    /// Creates the block; `retryIsPrimary` is false where the pane
    /// already has a primary action, such as a worktree's own form.
    public init(worktree: Worktree, failure: LaunchFailure, model: DashboardModel, retryIsPrimary: Bool) {
        self.worktree = worktree
        self.failure = failure
        self.model = model
        self.retryIsPrimary = retryIsPrimary
    }

    // MARK: Public

    public var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            Label("The agent did not start", systemImage: "exclamationmark.triangle.fill")
                .interfaceFont(.headline)
            Text(failure.message)
                .interfaceFont(.callout)
                .foregroundStyle(.red)
                .textSelection(.enabled)
            HStack {
                Spacer()
                if worktree.isPlaceholder {
                    Button("Dismiss") { model.dismissLaunchFailure(for: worktree) }
                        .buttonStyle(.glass)
                        .hoverHelp("Remove this row; nothing was created")
                }
                if retryIsPrimary {
                    retryButton.buttonStyle(.glassProminent)
                } else {
                    retryButton.buttonStyle(.glass)
                }
            }
        }
    }

    // MARK: Private

    private static let spacing: CGFloat = 8

    private let worktree: Worktree
    private let failure: LaunchFailure
    private let model: DashboardModel
    private let retryIsPrimary: Bool

    private var retryButton: some View {
        Button("Edit and retry") { model.retryLaunch(for: worktree) }
            .hoverHelp(
                worktree.isPlaceholder
                    ? "Open the new session form as this launch was started: what was typed, its source and base branch"
                    : "Put what was typed and its source back in the form below",
            )
    }
}

// MARK: - DashboardModel

public extension DashboardModel {
    /// The failure to show on a row; a session running there since
    /// has settled it.
    func launchFailure(for item: WorktreeItem) -> LaunchFailure? {
        if item.session == nil {
            launchFailures[item.worktree.path]
        } else {
            nil
        }
    }

    /// Drops a failure, and with it a placeholder's row, which hands
    /// a selection it held to its repository's checkout.
    func dismissLaunchFailure(for worktree: Worktree) {
        launchFailures[worktree.path] = nil
        guard worktree.isPlaceholder else {
            return
        }

        if selection?.worktree.path == worktree.path {
            selectMainCheckout(of: repository(of: worktree))
        }
        forgetPlaceholder(worktree)
    }

    /// Hands a failed launch's draft back to the form that started
    /// it: a placeholder gives way to the new session form on its
    /// repository and base, and a worktree's own form is already on
    /// screen.
    func retryLaunch(for worktree: Worktree) {
        guard let failure = launchFailures[worktree.path] else {
            return
        }

        let owner = repository(of: worktree)
        dismissLaunchFailure(for: worktree)
        launchRetry = LaunchRetry(
            repositoryPath: worktree.repositoryPath,
            worktreePath: worktree.isPlaceholder ? nil : worktree.path,
            draft: failure.draft,
        )
        if worktree.isPlaceholder {
            openNewSession(for: owner, base: failure.draft.base)
        }
    }

    /// The log a row's launch narrates into, or the shared one that
    /// resumes use.
    func launchProgress(for item: WorktreeItem) -> LaunchProgress {
        launchProgresses[item.worktree.path] ?? launchProgress
    }

    private func repository(of worktree: Worktree) -> Repository? {
        groups.first { $0.repository.path == worktree.repositoryPath }?.repository
    }
}
