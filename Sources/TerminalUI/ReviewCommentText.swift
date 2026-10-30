import SanductorDomain
import SwiftUI

/// A review body without the bots' command advertisements.
public struct ReviewCommentText: View {
    // MARK: Lifecycle

    public init(_ text: String, author: String) {
        if let bot = ReviewBot.allCases.first(where: { $0.matches(author) }) {
            self.text = Self.cache.value(for: bot.rawValue + "\0" + text) { _ in
                Self.cleaned(text, isCodeRabbit: bot == .codeRabbit)
            }
        } else {
            self.text = text
        }
    }

    // MARK: Public

    public var body: some View {
        MarkdownText(text)
    }

    // MARK: Internal

    let text: String

    // MARK: Private

    private static let cache: MarkdownText.ParseCache<String> = .init()

    private static func cleaned(_ text: String, isCodeRabbit: Bool) -> String {
        guard let protected = try? protectedMarkdown(text, isCodeRabbit: isCodeRabbit) else {
            return text
        }

        return protected.restore((isCodeRabbit ? withoutNotices(protected.source) : protected.source)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { line in
                let content = MarkdownText.content(protected.restore(String(line)))
                guard content.runs.contains(where: { run in
                    run.presentationIntent?.components.contains { component in
                        if case .codeBlock = component.kind {
                            return true
                        }
                        return false
                    } == true
                }) == false else {
                    return true
                }

                let visible = String(content.characters)
                    .trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n☐☑•."))
                if isCodeRabbit, visible == "❤️ Share" {
                    return false
                }
                return visible != "Review in Change Stack →" && ReviewBot.allCases.contains { bot in
                    visible == "Comment @" + bot.login + " help to get the list of available commands"
                        || visible == "Autofix · Keep fixing " + bot.displayName
                        + " findings and required CI, and resolving merge conflicts"
                } == false
            }
            .joined(separator: "\n"))
    }
}
