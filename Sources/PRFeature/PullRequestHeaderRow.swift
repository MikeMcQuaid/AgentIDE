import AgentIDEDomain
import SwiftUI
import TerminalUI

// MARK: - PullRequestHeaderRow

/// Shared list and conversation header with a fixed height and
/// space for the back chevron, so opening a PR never shifts its title.
/// The conversation supplies its label and autofix toolbar actions.
struct PullRequestHeaderRow: View {
    // MARK: Internal

    let summary: PullRequestSummary
    let stackDepth: Int

    /// Nil in the list, where there is nothing to go back to.
    let onBack: (() -> Void)?

    let onCopyComments: @MainActor () async -> Void
    let onOpenChecks: @MainActor () async -> Void

    /// Opens the title and body for editing, on the conversation's
    /// header alone.
    var onEdit: (@MainActor () -> Void)?
    var onAskBot: (@MainActor (ReviewBot) async -> Bool)?
    var requestableBots: Set = .init(ReviewBot.allCases)
    var reviewBot: ReviewBot?
    var toolbarActions: AnyView?

    var body: some View {
        HStack(spacing: Self.spacing) {
            Button("Back to the list", systemImage: "chevron.backward") { onBack?() }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(onBack == nil)
                .opacity(onBack == nil ? 0 : 1)
                .hoverHelp("Back to the pull request list")
            PullRequestRowView(
                summary: summary,
                stackDepth: stackDepth,
                showsActions: true,
                onCopyComments: onCopyComments,
                onOpenChecks: onOpenChecks,
                onEdit: onEdit,
                onAskBot: onAskBot,
                requestableBots: requestableBots,
                reviewBot: reviewBot,
                toolbarActions: toolbarActions,
            )
        }
        .padding(.horizontal, Self.padding)
        // The fixed height: a light row growing icons as the full
        // fetch lands never moves the page under the reader.
        .frame(height: Self.height)
    }

    // MARK: Private

    private static let height: CGFloat = 46
    private static let spacing: CGFloat = 4
    private static let padding: CGFloat = 8
}
