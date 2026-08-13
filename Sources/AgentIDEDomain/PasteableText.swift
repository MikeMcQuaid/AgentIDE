/// Reflows terminal copies for pasting into prose tools like chat,
/// notes and pull request bodies: indentation and the hard line
/// breaks terminal width forced go, blank lines keep paragraphs
/// apart and list items keep their own lines.
public enum PasteableText {
    // MARK: Public

    /// The reflowed text; single lines just lose surrounding
    /// whitespace.
    public static func reflow(_ text: String) -> String {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard content.contains("\n") else {
            return content
        }

        var blocks = [(text: String, isListItem: Bool)]()
        var current: (text: String, isListItem: Bool)?
        for raw in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
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

    // MARK: Private

    /// Bullets, quotes and numbered items start their own lines and
    /// swallow their wrapped continuations.
    private static func isListItem(_ line: String) -> Bool {
        for marker in ["- ", "* ", "+ ", "• ", "· ", "◦ ", "▸ ", "☐ ", "☒ ", "> "]
            where line.hasPrefix(marker) {
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
