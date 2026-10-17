import SwiftUI
import TerminalUI

/// Keeps the conversation mounted while the checks list or log is visible.
extension PullRequestConversationPane {
    func checksAndConversation(showsChecks: Binding<Bool>) -> some View {
        VStack(spacing: 0) {
            Picker("Pull request content", selection: showsChecks) {
                Text("Conversation").tag(false)
                Text(summary.checkDetails.map { "Checks " + String($0.count) } ?? "Checks").tag(true)
            }
            .pickerStyle(.segmented)
            .padding(Self.labelsPadding)
            ZStack {
                PullRequestConversationView(
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
                .hidden(showsChecks.wrappedValue)
                .accessibilityHidden(showsChecks.wrappedValue)
                if showsChecks.wrappedValue {
                    PullRequestChecksView(model: model, summary: summary)
                        .id(summary.url)
                }
            }
        }
    }
}
