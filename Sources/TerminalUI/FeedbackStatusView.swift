import AgentIDEData
import AgentIDEDomain
import SwiftUI

/// Active work alone earns space beneath the toolbar.
public struct FeedbackStatusView: View {
    // MARK: Lifecycle

    public init(service: SessionService, repositoryPath: String, worktreePath: String?, summary: PullRequestSummary?) {
        self.service = service
        self.repositoryPath = repositoryPath
        self.worktreePath = worktreePath
        self.summary = summary
    }

    // MARK: Public

    public var body: some View {
        if state.isAutomatic || state.isPausedForReview || state.attempt != nil {
            Text(state.activityStatus)
                .interfaceFont(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .hoverHelp(state.activityStatus)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Self.padding)
        }
    }

    // MARK: Private

    private static let padding: CGFloat = 8

    @AppStorage(UtilityTabTarget.pullRequestCacheKey)
    private var generation = 0

    private let service: SessionService
    private let repositoryPath: String
    private let worktreePath: String?
    private let summary: PullRequestSummary?

    private var state: PullRequestAutomation {
        _ = generation
        return service.feedbackState(repositoryPath: repositoryPath, worktreePath: worktreePath, summary: summary)
    }
}
