import AgentIDEData
import AgentIDEDomain
import SwiftUI
import TerminalUI

/// A pull request's conversation: its description, then every review
/// and comment down a timeline rail.
struct PullRequestConversationView: View {
    // MARK: Internal

    let github: GitHubClient
    let repositoryPath: String
    let number: Int

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Self.eventSpacing) {
                if isLoading {
                    ProgressView("Loading conversation…")
                        .frame(maxWidth: .infinity, minHeight: Self.loadingHeight)
                } else {
                    content
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Self.padding)
        }
        // State clears instantly on arrival, so a previous pull
        // request's conversation never lingers while this one loads.
        .task(id: number) {
            isLoading = true
            description = ""
            events = []
            let conversation = await github.conversation(repositoryPath: repositoryPath, number: number)
            description = conversation.body
            events = conversation.events
            isLoading = false
        }
    }

    // MARK: Private

    private static let padding: CGFloat = 8
    private static let eventSpacing: CGFloat = 10
    private static let headerSpacing: CGFloat = 4
    private static let railWidth: CGFloat = 2
    private static let railInset: CGFloat = 10
    private static let loadingHeight: CGFloat = 120

    @State private var description = ""
    @State private var events: [ReviewComment] = []
    @State private var isLoading = true

    @ViewBuilder private var content: some View {
        if description.isEmpty == false {
            MarkdownText(description).font(.caption)
            Divider()
        }
        ForEach(events) { event in
            eventRow(event)
        }
        if events.isEmpty, description.isEmpty {
            Text("No description or feedback yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// One timeline entry: the author and review type over the body,
    /// beside the rail.
    private func eventRow(_ event: ReviewComment) -> some View {
        VStack(alignment: .leading, spacing: Self.headerSpacing) {
            HStack(spacing: Self.headerSpacing) {
                Text(ChecksStyle.authorDisplayName(event.author)).font(.caption.bold())
                if let icon = ChecksStyle.reviewOcticonName(for: event.kind) {
                    Octicon(icon, colour: ChecksStyle.reviewColour(for: event.kind))
                    Text(event.kind.replacing("_", with: " ").lowercased())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if event.body.isEmpty == false {
                MarkdownText(event.body).font(.caption)
            }
        }
        .padding(.leading, Self.railInset)
        .overlay(alignment: .leading) {
            Rectangle().fill(.separator).frame(width: Self.railWidth)
        }
    }
}
