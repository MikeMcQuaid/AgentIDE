import AgentIDEData
import AgentIDEDomain
import SwiftUI
import TerminalUI

// MARK: - PullRequestConversationPane

/// The conversation page: the back button and full header row over
/// the timeline.
struct PullRequestConversationPane: View {
    // MARK: Internal

    let summary: PullRequestSummary
    let stackDepth: Int
    let hasMergeQueue: Bool
    let github: GitHubClient
    let repositoryPath: String
    let store: MetadataStore
    let onBack: () -> Void
    let onAutomerge: @MainActor () async -> Void
    let onMerge: @MainActor () async -> Void
    let onCopyComments: @MainActor () async -> Void
    let onCopyChecks: @MainActor () async -> Void
    let onResolveAll: @MainActor () async -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Self.spacing) {
                Button("Back to the list", systemImage: "chevron.backward", action: onBack)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .hoverHelp("Back to the pull request list")
                PullRequestRowView(
                    summary: summary,
                    stackDepth: stackDepth,
                    hasMergeQueue: hasMergeQueue,
                    showsActions: true,
                    onAutomerge: onAutomerge,
                    onMerge: onMerge,
                    onCopyComments: onCopyComments,
                    onCopyChecks: onCopyChecks,
                    onResolveAll: onResolveAll,
                )
            }
            .padding(.horizontal, Self.padding)
            Divider()
            PullRequestConversationView(
                github: github,
                repositoryPath: repositoryPath,
                number: summary.number,
                seededBody: summary.body,
                store: store,
            )
        }
    }

    // MARK: Private

    private static let spacing: CGFloat = 4
    private static let padding: CGFloat = 8
}

// MARK: - PullRequestConversationView

/// A pull request's conversation: its description, then every review
/// and comment down a timeline rail.
struct PullRequestConversationView: View {
    // MARK: Internal

    let github: GitHubClient
    let repositoryPath: String
    let number: Int

    /// The description already carried by the listing, shown before
    /// any fetch answers.
    let seededBody: String?

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
        // The listing's body or the cached conversation paints
        // instantly (or the state clears, so another pull request's
        // never lingers) while the fetch refreshes and re-caches. A
        // seeded body is fresh from the listing, so only the events
        // need fetching. Failures and cancelled fetches change and
        // cache nothing, keeping the last good conversation.
        .task(id: number) {
            isLoading = true
            defer { isLoading = false }
            let cached = store.load().conversationCache[cacheKey]
            description = seededBody ?? cached?.body ?? ""
            events = cached?.events ?? []
            do {
                let freshBody: String
                let freshEvents: [ReviewComment]
                if let seededBody {
                    freshBody = seededBody
                    freshEvents = try await github.reviewComments(repositoryPath: repositoryPath, number: number)
                } else {
                    (freshBody, freshEvents) = try await github.conversation(
                        repositoryPath: repositoryPath,
                        number: number,
                    )
                }
                guard Task.isCancelled == false else {
                    return
                }

                description = freshBody
                events = freshEvents
                var metadata = store.load()
                metadata.conversationCache[cacheKey] = CachedConversation(body: freshBody, events: freshEvents)
                store.save(metadata)
            } catch {
                // The painted cache stays; the failure only logs.
                ErrorLog.shared.report(error.localizedDescription)
            }
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
