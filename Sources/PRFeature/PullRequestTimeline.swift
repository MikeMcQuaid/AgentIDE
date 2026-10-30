import SanductorDomain
import SwiftUI
import TerminalUI

/// The description, human comments and latest entry from each review bot.
struct PullRequestTimeline: View {
    // MARK: Lifecycle

    init(description: String, events: [ReviewComment]) {
        self.description = description
        var counts = [ReviewBot: Int]()
        self.events = events.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
            .reversed()
            .filter { event in
                guard let bot = ReviewBot.allCases.first(where: { $0.matches(event.author) }) else {
                    return true
                }

                counts[bot, default: 0] += 1
                return counts[bot] == 1
            }
            .reversed()
        botCommentCounts = counts
    }

    // MARK: Internal

    static let spacing: CGFloat = 10

    let description: String
    let events: [ReviewComment]

    var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            if description.isEmpty == false {
                MarkdownText(description)
                Divider()
            }
            ForEach(events) { event in
                VStack(alignment: .leading, spacing: Self.headerSpacing) {
                    header(for: event)
                    if event.body.isEmpty == false {
                        ReviewCommentText(event.body, author: event.author)
                    }
                }
                .padding(.leading, Self.spacing)
                .overlay(alignment: .leading) {
                    Rectangle().fill(.separator).frame(width: Self.railWidth)
                }
            }
        }
    }

    func headerDetail(for event: ReviewComment) -> String {
        var parts = [String]()
        if let date = event.date {
            parts.append(date.formatted(date: .abbreviated, time: .shortened))
        }
        if let bot = ReviewBot.allCases.first(where: { $0.matches(event.author) }),
           let count = botCommentCounts[bot], count > 1
        {
            parts.append("Latest of " + String(count) + " comments")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Private

    private static let headerSpacing: CGFloat = 4
    private static let railWidth: CGFloat = 2

    private let botCommentCounts: [ReviewBot: Int]

    private func header(for event: ReviewComment) -> some View {
        HStack(spacing: Self.headerSpacing) {
            ConversationAuthor(event.author)
            if let icon = ChecksStyle.reviewOcticonName(for: event.kind) {
                Octicon(icon, colour: ChecksStyle.reviewColour(for: event.kind))
                Text(event.kind.replacing("_", with: " ").lowercased())
                    .interfaceFont(.callout)
                    .foregroundStyle(.secondary)
            }
            let detail = headerDetail(for: event)
            if detail.isEmpty == false {
                Text(detail)
                    .interfaceFont(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .hoverHelp(detail)
            }
        }
    }
}
