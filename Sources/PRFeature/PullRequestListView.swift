import AgentIDEDomain
import SwiftUI
import TerminalUI

/// The paginated pull request title list: state icon, number and
/// title per row, each clicking through to its conversation.
struct PullRequestListView: View {
    // MARK: Internal

    /// One fetch page; the tab grows its query limit in these steps.
    static let pageSize = 25

    let summaries: [PullRequestSummary]
    let isLoading: Bool

    /// Whether the last fetch filled its limit, so later pages may
    /// exist beyond what is loaded.
    let hasMore: Bool

    let stackDepth: (PullRequestSummary) -> Int

    /// The selection closure is a non-final property so call sites
    /// keep it labelled; a trailing closure after the multiline call
    /// fights SwiftFormat.
    let onSelect: (PullRequestSummary) -> Void

    @Binding var page: Int

    var body: some View {
        VStack(spacing: 0) {
            List(pageSummaries) { summary in
                row(summary)
            }
            .overlay {
                if isLoading, summaries.isEmpty {
                    ProgressView("Loading pull requests…")
                } else if summaries.isEmpty {
                    ContentUnavailableView("No pull requests", systemImage: "arrow.triangle.pull")
                }
            }
            if summaries.count > Self.pageSize || hasMore {
                Divider()
                pager
            }
        }
    }

    // MARK: Private

    private static let rowSpacing: CGFloat = 4
    private static let pagerSpacing: CGFloat = 8

    private var pageSummaries: [PullRequestSummary] {
        Array(summaries.dropFirst(page * Self.pageSize).prefix(Self.pageSize))
    }

    private var pager: some View {
        let last = min(summaries.count, (page + 1) * Self.pageSize)
        return HStack(spacing: Self.pagerSpacing) {
            Spacer()
            Button("Previous page", systemImage: "chevron.backward") { page -= 1 }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(page == 0)
                .hoverHelp("The previous \(Self.pageSize) pull requests")
            Text(String(page * Self.pageSize + 1) + "–" + String(last) + " of " + String(summaries.count))
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Next page", systemImage: "chevron.forward") { page += 1 }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(last >= summaries.count && hasMore == false)
                .hoverHelp("The next \(Self.pageSize) pull requests")
            Spacer()
        }
        .padding(Self.rowSpacing)
    }

    /// The conversation header's own look, without its actions; a
    /// click anywhere outside the inner links opens the conversation.
    private func row(_ summary: PullRequestSummary) -> some View {
        PullRequestRowView(
            summary: summary,
            canRemediate: false,
            stackDepth: stackDepth(summary),
            hasMergeQueue: false,
            showsActions: false,
            onAutomerge: noAction,
            onMerge: noAction,
            onRemediate: noAction,
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect(summary) }
        .accessibilityAddTraits(.isButton)
        .hoverHelp("Open this pull request's conversation")
    }

    /// Rows hide their actions but the parameters remain.
    private func noAction() {
        // Never called: the action buttons are not rendered.
    }
}
