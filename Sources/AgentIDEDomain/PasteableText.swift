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

        let blocks = blocks(in: content)
        var result = ""
        for (index, block) in blocks.enumerated() where block.text.isEmpty == false {
            if index > 0 {
                result += separator(before: block, after: blocks[index - 1])
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

    // MARK: Private

    /// What a run of lines is, which decides whether it may be
    /// joined into one line.
    private enum Kind {
        /// Wrapped prose, joined back into one line.
        case paragraph
        /// A bullet or numbered item, which keeps its own line and
        /// swallows its wrapped continuations.
        case listItem
        /// Commands or code, kept exactly as they are: joining
        /// `git fetch` onto the `cd` before it turns a runnable
        /// script into one broken line.
        case code
    }

    private struct Block {
        var text: String
        var kind: Kind
        /// Whether a blank line stood before it, which decides
        /// whether it is a new paragraph or the next line of one
        /// thing.
        var followsBlank: Bool
    }

    /// The block glyphs terminal interfaces use as gutters and
    /// borders.
    private static let gutterMarks: Set<Character> = ["▎", "▏", "▍", "│", "┃"]

    /// Shell command words that begin a code line; the list is small
    /// on purpose and other lines qualify through their punctuation.
    private static let commandWords: Set<String> = [
        "cd", "git", "ls", "cat", "echo", "export", "sudo", "brew", "npm", "swift", "xcodebuild",
        "make", "curl", "python", "python3", "ruby", "bundle", "rm", "mkdir", "cp", "mv", "herdr",
        "gh", "docker", "ssh", "source", "exec", "printf", "grep", "sed", "awk", "find", "chmod",
    ]

    /// Whether a line opens the way a sentence does: with a capital
    /// letter, a quotation mark or an opening bracket, and without
    /// the signature of a command. Lowercase openings are how
    /// commands, paths and flags begin, and they stay as copied.
    private static func readsAsProse(_ line: String) -> Bool {
        guard let first = line.first, hasCodeSignature(line) == false else {
            return false
        }

        return first.isUppercase || "\"'“‘(".contains(first)
    }

    /// Gathers the lines into blocks. A blank line ends whatever is
    /// open, a list marker starts its own item, a line that reads as
    /// a command starts or continues a code block, and any other
    /// line continues the current one. Classifying per block rather
    /// than per copy is what lets an agent's answer of a sentence,
    /// then a script, then another sentence come out with the
    /// sentences reflowed and the script still runnable.
    private static func blocks(in content: String) -> [Block] {
        var blocks = [Block]()
        var current: Block?
        var followsBlank = false
        for raw in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = strippingGutter(String(raw))
            guard line.isEmpty == false else {
                if let block = current {
                    blocks.append(block)
                    current = nil
                }
                followsBlank = true
                continue
            }

            // Verbatim unless the line proves itself prose: a command
            // wrongly joined onto its neighbour is broken, a sentence
            // left on its own line is merely untidy, so the doubt
            // goes to keeping the line. A line continues the prose
            // above it only while that prose is still open.
            let continuesProse = (current?.kind == .paragraph || current?.kind == .listItem)
                && hasCodeSignature(line) == false
            let kind: Kind =
                if startsCode(line) {
                    .code
                } else if isListItem(line) {
                    .listItem
                } else if readsAsProse(line) || continuesProse {
                    .paragraph
                } else {
                    .code
                }
            if var block = current, block.kind == kind, kind != .listItem {
                // Code keeps its line breaks; prose loses them.
                block.text += kind == .code ? "\n" + line : " " + line
                current = block
            } else if var block = current, kind == .paragraph, block.kind == .listItem {
                block.text += " " + line
                current = block
            } else {
                if let block = current {
                    blocks.append(block)
                }
                current = Block(text: line, kind: kind, followsBlank: followsBlank)
                followsBlank = false
            }
        }
        if let block = current {
            blocks.append(block)
        }
        return blocks
    }

    /// What goes between two blocks: what the copy had where it had
    /// a blank line, one line between the items of a list, and one
    /// between prose and the commands it introduces, since a
    /// sentence and its command belong together.
    private static func separator(before block: Block, after previous: Block) -> String {
        if block.followsBlank {
            return "\n\n"
        }
        if block.kind == .listItem, previous.kind == .listItem {
            return "\n"
        }

        return block.kind == .code || previous.kind == .code ? "\n" : "\n\n"
    }

    /// Whether a line opens like a command: a shell word, a prompt,
    /// a path or a shebang at its start. Weaker signs of code, a
    /// flag or a pipe somewhere in the line, deliberately do not
    /// count here, or a sentence mentioning `--verbose` would stop
    /// being prose.
    private static func startsCode(_ line: String) -> Bool {
        let first = line.split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
        return commandWords.contains(first)
            || first.hasPrefix("$")
            || first.hasPrefix("./")
            || first.hasPrefix("~/")
            || line.hasPrefix("#!")
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
