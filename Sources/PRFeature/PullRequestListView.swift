import AgentIDEDomain
import SwiftUI
import TerminalUI

/// The paginated pull request title list: state icon, number and
/// title per row, each clicking through to its conversation.
struct PullRequestListView: View {
    // MARK: Internal

    let summaries: [PullRequestSummary]
    let isLoading: Bool
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
                if isLoading {
                    ProgressView("Loading pull requests…")
                } else if summaries.isEmpty {
                    ContentUnavailableView("No pull requests", systemImage: "arrow.triangle.pull")
                }
            }
            if summaries.count > Self.pageSize {
                Divider()
                pager
            }
        }
    }

    // MARK: Private

    private static let pageSize = 25
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
                .disabled(last >= summaries.count)
                .hoverHelp("The next \(Self.pageSize) pull requests")
            Spacer()
        }
        .padding(Self.rowSpacing)
    }

    private func row(_ summary: PullRequestSummary) -> some View {
        Button {
            onSelect(summary)
        } label: {
            HStack(spacing: Self.rowSpacing) {
                Octicon(
                    ChecksStyle.stateOcticonName(state: summary.state, isDraft: summary.isDraft),
                    colour: ChecksStyle.stateColour(state: summary.state, isDraft: summary.isDraft),
                )
                Text("#" + String(summary.number)).font(.callout).foregroundStyle(.secondary)
                Text(summary.title).font(.callout).lineLimit(1)
                if stackDepth(summary) > 1 {
                    Octicon("octicon-stack", colour: .secondary)
                        .hoverHelp("Stacked: \(stackDepth(summary)) pull requests based on each other")
                    Text(String(stackDepth(summary))).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHelp("Open this pull request's conversation")
    }
}
