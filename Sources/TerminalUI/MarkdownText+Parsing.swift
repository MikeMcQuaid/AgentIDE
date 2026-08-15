import AgentIDEDomain
import Foundation

/// The markdown parsing behind the view, split from the view body
/// for length.
extension MarkdownText {
    /// One monospaced or prose run of a chunk.
    struct Segment {
        let text: String
        let isCode: Bool
        var language: SyntaxLanguage?
    }

    /// One structural piece of prose: GitHub comments mix headings,
    /// horizontal rules and pipe tables into their markdown.
    enum ProseBlock {
        case heading(String)
        case rule
        case table(header: [String], rows: [[String]])
        case text(String)
    }

    /// The shortest run of `-` or `*` that reads as a rule.
    static let ruleMinimumLength = 3

    /// A table needs a header row and a separator row.
    static let tableHeaderRows = 2

    static func proseBlocks(_ text: String) -> [ProseBlock] {
        var blocks = [ProseBlock]()
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var index = 0
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                index += 1
            } else if trimmed.hasPrefix("#") {
                blocks.append(.heading(trimmed.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)))
                index += 1
            } else if isRule(trimmed) {
                blocks.append(.rule)
                index += 1
            } else if trimmed.hasPrefix("|") {
                blocks.append(tableBlock(lines, from: &index))
            } else {
                blocks.append(textBlock(lines, from: &index))
            }
        }
        return blocks
    }

    /// Whether a line is a `---` or `***` horizontal rule.
    static func isRule(_ trimmed: String) -> Bool {
        trimmed.count >= ruleMinimumLength
            && (Set(trimmed).isSubset(of: ["-"]) || Set(trimmed).isSubset(of: ["*"]))
    }

    /// The trimmed cells of one `| a | b |` row.
    static func cells(of row: String) -> [String] {
        row.trimmingCharacters(in: CharacterSet(charactersIn: "|"))
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Whether a row is the `|---|:--|` header separator.
    static func isSeparatorRow(_ cells: [String]) -> Bool {
        cells.isEmpty == false && cells.allSatisfy { cell in
            cell.isEmpty == false && cell.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }

    /// The fence tag's language, tolerating common aliases.
    static func syntaxLanguage(for tag: String) -> SyntaxLanguage? {
        switch tag.trimmingCharacters(in: .whitespaces).lowercased() {
        case "swift":
            .swift

        case "rb",
             "ruby":
            .ruby

        case "bash",
             "sh",
             "shell",
             "zsh":
            .shell

        case "py",
             "python":
            .python

        case "json":
            .json

        case "dockerfile":
            .dockerfile

        case "ts",
             "tsx",
             "typescript":
            .typescript

        case "yaml",
             "yml":
            .yaml

        case "markdown",
             "md":
            .markdown

        default:
            nil
        }
    }

    /// Drops HTML comments, unwraps the details and summary tags
    /// bots fold their reports into, and converts anchors and line
    /// breaks to their markdown equivalents.
    static func strippingHTML(_ text: String) -> String {
        var stripped = text.replacing(/<!--[\s\S]*?-->/, with: "")
        stripped = stripped.replacing(/<a\s+[^>]*href="([^"]*)"[^>]*>([\s\S]*?)<\/a>/) { match in
            "[" + String(match.output.2) + "](" + String(match.output.1) + ")"
        }
        stripped = stripped.replacing(/<br\s*\/?>/, with: "\n")
        stripped = stripped.replacing(/<img[^>]*>/, with: "")
        // Bots write HTML lists and code spans (dependabot's commit
        // listings); they map straight onto markdown.
        stripped = stripped.replacing(/<li>\s*/.ignoresCase(), with: "\n- ")
        stripped = stripped.replacing(/<\/li>/.ignoresCase(), with: "")
        stripped = stripped.replacing(/<\/?[uo]l>/.ignoresCase(), with: "\n")
        stripped = stripped.replacing(/<\/?code>/.ignoresCase(), with: "`")
        stripped = stripped.replacing(/<\/?p>/.ignoresCase(), with: "\n")
        for tag in ["<details>", "</details>", "<summary>", "</summary>"] {
            stripped = stripped.replacingOccurrences(of: tag, with: "", options: .caseInsensitive)
        }
        // `[//]: #` lines are markdown comments (dependabot's
        // automerge markers) and render as nothing.
        return stripped
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("[//]: #") == false }
            .joined(separator: "\n")
    }

    static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
        )
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    /// Consecutive prose lines, blank separators included, gather
    /// into one block so a single Text renders them and selection
    /// can span lines and paragraphs.
    private static func textBlock(_ lines: [String], from index: inout Int) -> ProseBlock {
        var gathered = [String]()
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("#") == false, isRule(trimmed) == false,
                  trimmed.hasPrefix("|") == false
            else {
                break
            }

            gathered.append(lines[index])
            index += 1
        }
        while gathered.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            gathered.removeLast()
        }
        return .text(gathered.joined(separator: "\n"))
    }

    /// The pipe rows from the current line onwards as one table.
    private static func tableBlock(_ lines: [String], from index: inout Int) -> ProseBlock {
        var rows = [[String]]()
        while index < lines.count {
            let row = lines[index].trimmingCharacters(in: .whitespaces)
            guard row.hasPrefix("|") else {
                break
            }

            rows.append(cells(of: row))
            index += 1
        }
        if rows.count >= tableHeaderRows, isSeparatorRow(rows[1]) {
            return .table(header: rows[0], rows: Array(rows.dropFirst(tableHeaderRows)))
        }
        return .table(header: [], rows: rows)
    }
}
