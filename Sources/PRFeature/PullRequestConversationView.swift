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
    let store: MetadataStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Self.eventSpacing) {
                if isLoading, events.isEmpty, description.isEmpty {
                    ProgressView("Loading conversation…")
                        .frame(maxWidth: .infinity, minHeight: Self.loadingHeight)
                } else {
                    content
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Self.padding)
        }
        // The cached conversation paints instantly (or the state
        // clears, so another pull request's never lingers) while the
        // fetch refreshes and re-caches.
        .task(id: number) {
            isLoading = true
            let cached = store.load().conversationCache[cacheKey]
            description = cached?.body ?? ""
            events = cached?.events ?? []
            let conversation = await github.conversation(repositoryPath: repositoryPath, number: number)
            description = conversation.body
            events = conversation.events
            var metadata = store.load()
            metadata.conversationCache[cacheKey] = CachedConversation(
                body: conversation.body,
                events: conversation.events,
            )
            store.save(metadata)
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

    private var cacheKey: String {
        repositoryPath + "#" + String(number)
    }

    @ViewBuilder private var content: some View {
        if description.isEmpty == false {
            MarkdownText(description)
            Divider()
        }
        ForEach(events) { event in
            eventRow(event)
        }
        if events.isEmpty, description.isEmpty {
            Text("No description or feedback yet.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    /// One timeline entry: the author and review type over the body,
    /// beside the rail.
    private func eventRow(_ event: ReviewComment) -> some View {
        VStack(alignment: .leading, spacing: Self.headerSpacing) {
            HStack(spacing: Self.headerSpacing) {
                Text(ChecksStyle.authorDisplayName(event.author)).font(.callout.bold())
                if let icon = ChecksStyle.reviewOcticonName(for: event.kind) {
                    Octicon(icon, colour: ChecksStyle.reviewColour(for: event.kind))
                    Text(event.kind.replacing("_", with: " ").lowercased())
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            if event.body.isEmpty == false {
                MarkdownText(event.body)
            }
        }
        .padding(.leading, Self.railInset)
        .overlay(alignment: .leading) {
            Rectangle().fill(.separator).frame(width: Self.railWidth)
        }
    }
}
