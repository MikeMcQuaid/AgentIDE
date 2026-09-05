import AgentIDEDomain
import Foundation
import Markdown

/// The markdown parsing behind the view: apple/swift-markdown reads
/// the GitHub-flavoured structure and the shapes here are what the
/// view renders. Split from the view body for length.
extension MarkdownText {
    /// One structural piece of a comment: GitHub comments mix
    /// headings, rules, fenced code and pipe tables into markdown.
    enum ProseBlock {
        case heading(String)
        case rule
        case code(String, SyntaxLanguage?)
        case table(header: [String], rows: [[String]])
        case image(source: String, alt: String)
        case text(String)
    }

    /// Parses one chunk with the official GitHub-flavoured parser,
    /// mapping its block structure onto the renderer's shapes.
    /// Consecutive prose blocks merge, so one Text renders them and
    /// selection can span paragraphs and lists.
    static func proseBlocks(_ text: String) -> [ProseBlock] {
        let document = Document(parsing: text)
        var blocks = [ProseBlock]()
        for child in document.blockChildren {
            switch child {
            case let heading as Heading:
                blocks.append(.heading(heading.plainText))

            case let code as CodeBlock:
                blocks.append(.code(
                    code.code.trimmingCharacters(in: .newlines),
                    syntaxLanguage(for: code.language ?? ""),
                ))

            case is ThematicBreak:
                blocks.append(.rule)

            case let table as Markdown.Table:
                blocks.append(.table(
                    header: table.head.cells.map { cellSource($0) },
                    rows: table.body.rows.map { row in row.cells.map { cellSource($0) } },
                ))

            case let paragraph as Paragraph where image(in: paragraph) != nil:
                // A paragraph holding nothing but an image is the
                // shape a screenshot takes in a README; anything
                // around it stays prose.
                if let found = image(in: paragraph) {
                    blocks.append(.image(source: found.source, alt: found.alt))
                }

            default:
                appendProse(reflowed(child.format()), to: &blocks)
            }
        }
        return blocks
    }

    /// The image a paragraph is, when that is all it is: the source
    /// and whatever alt text it carries.
    static func image(in paragraph: Paragraph) -> (source: String, alt: String)? {
        let children = Array(paragraph.inlineChildren).filter { inline in
            (inline as? Markdown.Text)?.string.trimmingCharacters(in: .whitespaces).isEmpty != true
        }
        guard children.count == 1, let image = children.first as? Markdown.Image,
              let source = image.source, source.isEmpty == false
        else {
            return nil
        }

        return (source, image.plainText)
    }

    /// Prose as GitHub renders it: a single newline inside a
    /// paragraph or a list item is a soft break, which joins rather
    /// than wrapping where the author's editor happened to. A blank
    /// line still ends a paragraph, a line git or markdown gives
    /// structure to (a heading, a quote, a list marker, a table row,
    /// a fence) starts afresh, and a line ending in two spaces or a
    /// backslash keeps the break it asked for.
    static func reflowed(_ text: String) -> String {
        var lines = [String]()
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            guard let previous = lines.last, continues(line, after: previous) else {
                lines.append(line)
                continue
            }

            lines[lines.count - 1] = previous + " " + line.trimmingCharacters(in: .whitespaces)
        }
        return lines.joined(separator: "\n")
    }

    /// Whether a line carries on the one before it rather than
    /// starting something of its own.
    private static func continues(_ line: String, after previous: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty == false
            && previous.trimmingCharacters(in: .whitespaces).isEmpty == false
            && previous.hasSuffix("  ") == false
            && previous.hasSuffix("\\") == false
            && starts(trimmed) == false
    }

    /// Whether a line begins something markdown gives its own shape.
    private static func starts(_ trimmed: String) -> Bool {
        let markers = ["- ", "* ", "+ ", "> ", "#", "|", "```", "~~~"]
        if markers.contains(where: trimmed.hasPrefix) {
            return true
        }

        // `1.` and friends: a number, a dot or bracket, a space.
        let digits = trimmed.prefix(while: \.isNumber)
        let rest = trimmed.dropFirst(digits.count)
        return digits.isEmpty == false && (rest.hasPrefix(". ") || rest.hasPrefix(") "))
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
        inlineCache.value(for: text) { text in
            let options = AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
            )
            let source = ticked(text)
            return (try? AttributedString(markdown: source, options: options)) ?? AttributedString(source)
        }
    }

    /// Task list markers render as their box glyphs: markdown's
    /// inline parser leaves `- [x]` as literal brackets, so a
    /// checklist read as punctuation rather than state.
    static func ticked(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { tickedLine(String($0)) }
            .joined(separator: "\n")
    }

    /// One line's task marker as its box glyph, the indentation and
    /// list marker kept so nesting still reads.
    private static func tickedLine(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for marker in ["- ", "* ", "+ "] where trimmed.hasPrefix(marker) {
            let rest = String(trimmed.dropFirst(marker.count))
            let indent = String(line.prefix(while: \.isWhitespace))
            if rest.hasPrefix("[ ] ") {
                return indent + marker + "\u{2610} " + rest.dropFirst("[ ] ".count)
            }
            if rest.lowercased().hasPrefix("[x] ") {
                return indent + marker + "\u{2611} " + rest.dropFirst("[x] ".count)
            }
        }
        return line
    }

    /// Merges consecutive prose into one block; the regenerated
    /// markdown keeps soft breaks, list markers and quote prefixes
    /// for the inline renderer.
    private static func appendProse(_ source: String, to blocks: inout [ProseBlock]) {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return
        }

        if case let .text(previous) = blocks.last {
            blocks[blocks.count - 1] = .text(previous + "\n\n" + trimmed)
        } else {
            blocks.append(.text(trimmed))
        }
    }

    /// One table cell's inline markdown source.
    private static func cellSource(_ cell: Markdown.Table.Cell) -> String {
        cell.inlineChildren.map { $0.format() }.joined().trimmingCharacters(in: .whitespaces)
    }
}
