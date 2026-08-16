import Foundation

/// Reflows terminal copies for pasting into prose tools like chat,
/// notes and pull request bodies: indentation and the hard line
/// breaks forced by the terminal's width are removed, blank lines
/// keep paragraphs apart and list items keep their own lines.
public enum PasteableText {
    // MARK: Public

    /// The reflowed text; single lines just lose surrounding
    /// whitespace and gutter marks.
    public static func reflow(_ text: String) -> String {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard content.contains("\n") else {
            return strippingGutter(content)
        }

        if let verbatim = codeBlock(content) {
            return verbatim
        }

        let blocks = proseBlocks(content)
        var result = ""
        for (index, block) in blocks.enumerated() {
            if index > 0 {
                // Consecutive list items stay a tight list; anything
                // else is a fresh paragraph.
                result += block.isListItem && blocks[index - 1].isListItem ? "\n" : "\n\n"
            }
            result += block.text
        }
        return result
    }

    /// A line without its leading gutter marks (the block glyphs
    /// terminal interfaces draw down their left edge) or
    /// surrounding whitespace.
    public static func strippingGutter(_ line: String) -> String {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        while let first = trimmed.first, Self.gutterMarks.contains(first) {
            trimmed = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        return trimmed
    }

    /// Whether stripped lines read as commands or code rather than
    /// prose: most non-blank lines carry a code signature (a shell
    /// command word, a path, an option flag, a pipe or redirect, a
    /// line continuation, or a prompt). Deliberately conservative
    /// so an ordinary sentence mentioning `--verbose` still reflows.
    public static func looksLikeCode(_ lines: [String]) -> Bool {
        let meaningful = lines.filter { $0.isEmpty == false }
        guard meaningful.count >= minimumCodeLines, let first = meaningful.first, hasCodeSignature(first) else {
            return false
        }

        return meaningful.filter(hasCodeSignature).count * codeMajority > meaningful.count
    }

    // MARK: Private

    /// One line alone is never a block; two can be.
    private static let minimumCodeLines = 2

    /// Signature lines times this must exceed the line count, so a
    /// strict majority of lines must look like code.
    private static let codeMajority = 2

    /// The block glyphs terminal interfaces use as gutters and
    /// borders.
    private static let gutterMarks: Set<Character> = ["▎", "▏", "▍", "│", "┃"]

    /// Shell command words that begin a code line; the list is small
    /// on purpose and other lines qualify through their punctuation.
    private static let commandWords: Set<String> = [
        "cd", "git", "ls", "cat", "echo", "export", "sudo", "brew", "npm", "swift", "xcodebuild",
        "make", "curl", "python", "python3", "ruby", "bundle", "rm", "mkdir", "cp", "mv", "tmux",
        "gh", "docker", "ssh", "source", "exec", "printf", "grep", "sed", "awk", "find", "chmod",
    ]

    /// Gathers prose into paragraphs and list items: a blank line
    /// ends a paragraph, a list marker starts its own item and any
    /// other line continues the current block.
    private static func proseBlocks(_ content: String) -> [(text: String, isListItem: Bool)] {
        var blocks = [(text: String, isListItem: Bool)]()
        var current: (text: String, isListItem: Bool)?
        for raw in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = strippingGutter(String(raw))
            if line.isEmpty {
                if let block = current {
                    blocks.append(block)
                    current = nil
                }
                continue
            }
            if isListItem(line) {
                if let block = current {
                    blocks.append(block)
                }
                current = (line, true)
            } else if let block = current {
                current = (block.text + " " + line, block.isListItem)
            } else {
                current = (line, false)
            }
        }
        if let block = current {
            blocks.append(block)
        }
        return blocks
    }

    /// Reflowing is for prose. A copied command block or code
    /// listing keeps its lines exactly, gutters stripped: joining
    /// `git fetch` onto the `cd` before it once turned a runnable
    /// script into one broken line. Nil when the text is prose.
    private static func codeBlock(_ content: String) -> String? {
        let stripped = content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { strippingGutter(String($0)) }
        return looksLikeCode(stripped) ? stripped.joined(separator: "\n") : nil
    }

    /// Whether one line carries a code signature.
    private static func hasCodeSignature(_ line: String) -> Bool {
        let first = line.split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
        if commandWords.contains(first) || first.hasPrefix("$") || first.hasPrefix("./") || first.hasPrefix("~/") {
            return true
        }
        if line.hasSuffix("\\") || line.hasPrefix("#!") || line.hasPrefix("//") {
            return true
        }
        // Flags, pipes, redirects and assignments rarely appear in
        // prose sentences and almost always in commands.
        return line.contains(" --") || line.contains(" | ") || line.contains(" > ") || line.contains(" && ")
            || line.contains(" -") && line.contains("/")
    }

    /// Bullets, quotes and numbered items start their own lines and
    /// swallow their wrapped continuations.
    private static func isListItem(_ line: String) -> Bool {
        let markers = ["- ", "* ", "+ ", "• ", "· ", "◦ ", "▸ ", "☐ ", "☒ ", "> "]
        if markers.contains(where: { line.hasPrefix($0) }) {
            return true
        }
        let digits = line.prefix(while: \.isNumber)
        guard digits.isEmpty == false else {
            return false
        }

        let rest = line.dropFirst(digits.count)
        return rest.hasPrefix(". ") || rest.hasPrefix(") ")
    }
}
