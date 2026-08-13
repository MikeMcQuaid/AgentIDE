import Foundation

/// Builds and parses pull request draft files: the first line is the
/// title and everything after the first blank line is the body, the
/// same shape as a git commit message.
public enum PullRequestDraft {
    // MARK: Public

    /// A draft from the repository's template: every markdown
    /// checkbox arrives prechecked and any AI disclosure line gains
    /// the disclosure text, so the editor opens with only the prose
    /// left to write.
    public static func compose(title: String, template: String?, disclosure: String?) -> String {
        var lines = (template ?? "")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { tick(String($0)) }
        if let disclosure {
            lines = disclosed(lines, with: disclosure)
        }
        let body = lines.joined(separator: "\n")
        return title + "\n\n" + body + (body.hasSuffix("\n") || body.isEmpty ? "" : "\n")
    }

    /// The draft split back into a title and body.
    public static func parse(_ content: String) -> (title: String, body: String) {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        let title = lines.first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        let body = lines.dropFirst()
            .drop { $0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (title, body)
    }

    /// One sentence naming what wrote the change, from whichever
    /// parts are known; nil when nothing is.
    public static func disclosure(agent: String?, model: String?, effort: String?) -> String? {
        var parts = [String]()
        if let agent, agent.isEmpty == false {
            parts.append(agent)
        }
        if let model, model.isEmpty == false {
            parts.append("model " + model)
        }
        if let effort, effort.isEmpty == false {
            parts.append(effort + " effort")
        }
        guard parts.isEmpty == false else {
            return nil
        }

        return parts.joined(separator: ", ")
    }

    // MARK: Private

    /// A checkbox line with its box ticked; other lines unchanged.
    private static func tick(_ line: String) -> String {
        let trimmed = line.drop { $0 == " " }
        guard trimmed.hasPrefix("- [ ]") || trimmed.hasPrefix("* [ ]") else {
            return line
        }
        guard let range = line.range(of: "[ ]") else {
            return line
        }

        return line.replacingCharacters(in: range, with: "[x]")
    }

    /// Whether a line is about AI use: a word-boundary match keeps
    /// "maintain" and friends from counting.
    private static func mentionsAI(_ line: String) -> Bool {
        line.range(of: #"(?i)\b(ai|llm|agent|assistant)\b"#, options: .regularExpression) != nil
    }

    /// Fills the first AI disclosure spot: a mentioning checkbox
    /// gains the text inline, a mentioning heading or labelled line
    /// gains it on the following line.
    private static func disclosed(_ lines: [String], with disclosure: String) -> [String] {
        var result = lines
        for (index, line) in lines.enumerated() where mentionsAI(line) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- [") || trimmed.hasPrefix("* [") {
                result[index] = line + ": " + disclosure
                return result
            }
            if trimmed.hasPrefix("#") || trimmed.hasSuffix(":") {
                result.insert(disclosure, at: index + 1)
                return result
            }
        }
        return result
    }
}
