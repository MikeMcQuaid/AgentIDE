import SwiftUI

/// Keeps the conversation mounted while the checks list or log is visible.
extension PullRequestConversationPane {
    var checksAndConversation: some View {
        PullRequestConversationView(
            model: model,
            summary: summary,
            github: github,
            repositoryPath: repositoryPath,
            number: summary.number,
            seededBody: summary.body,
            store: store,
            localReview: localReview,
            localWorktreePath: localWorktreePath,
            onToggleLocalResolved: onToggleLocalResolved,
            reloadToken: reloadToken,
            onResolvedChanged: onResolvedChanged,
            onThreadsChanged: onThreadsChanged,
            onReviewEventsChanged: onReviewEventsChanged,
        )
    }
}
