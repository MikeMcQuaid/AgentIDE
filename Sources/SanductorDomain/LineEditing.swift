/// The pure line edits behind the editor's shortcuts: comment
/// toggling, indentation and moving lines. Everything works on
/// whole lines, so the view maps a selection to its lines, hands
/// them over and writes the answer back.
public enum LineEditing {
    // MARK: Public

    /// The line-comment prefix a language toggles with, nil where
    /// the language has none worth typing (JSON allows no comments;
    /// Markdown's and HTML's are block markers).
    public static func commentPrefix(for language: SyntaxLanguage?) -> String? {
        switch language {
        case .cpp,
             .cSource,
             .golang,
             .java,
             .php,
             .rust,
             .swift,
             .typescript:
            "//"

        case .config,
             .dockerfile,
             .gitMessage,
             .gitRebaseTodo,
             .python,
             .ruby,
             .shell,
             .yaml:
            "#"

        case .css,
             .erb,
             .generic,
             .html,
             .json,
             .markdown,
             nil,
             .regex:
            nil
        }
    }

    /// Comments the block when any non-blank line is uncommented,
    /// uncomments every line otherwise. The prefix lands after the
    /// shallowest indentation of the block, so alignment survives
    /// the round trip; blank lines are left alone.
    public static func toggledComment(_ lines: [String], prefix: String) -> [String] {
        let considered = lines.filter { $0.isEmpty == false }
        guard considered.isEmpty == false else {
            return lines
        }

        let commented = considered.allSatisfy { line in
            line.drop { $0 == " " || $0 == "\t" }.hasPrefix(prefix)
        }
        guard commented else {
            let column = considered.lazy.map { leadingWhitespace(of: $0).count }.min() ?? 0
            return lines.map { line in
                guard line.isEmpty == false else {
                    return line
                }

                let split = line.index(line.startIndex, offsetBy: column)
                return String(line[..<split]) + prefix + " " + line[split...]
            }
        }

        return lines.map { line in
            let indent = leadingWhitespace(of: line)
            var body = line.dropFirst(indent.count)
            guard body.hasPrefix(prefix) else {
                return line
            }

            body = body.dropFirst(prefix.count)
            if body.first == " " {
                body = body.dropFirst()
            }
            return String(indent) + body
        }
    }

    /// Prepends the unit to every non-blank line.
    public static func indented(_ lines: [String], unit: String) -> [String] {
        lines.map { $0.isEmpty ? $0 : unit + $0 }
    }

    /// Removes up to one unit of leading whitespace from each line:
    /// a partial indent loses what is there rather than the line's
    /// first characters.
    public static func dedented(_ lines: [String], unit: String) -> [String] {
        lines.map { line in
            guard line.hasPrefix(unit) else {
                let removable = line.prefix { $0 == " " || $0 == "\t" }.prefix(unit.count)
                return String(line.dropFirst(removable.count))
            }

            return String(line.dropFirst(unit.count))
        }
    }

    /// The block moved one line up or down, with where it landed;
    /// nil at the file's edge, where there is nowhere to go.
    public static func moved(
        _ lines: [String],
        in range: Range<Int>,
        upwards: Bool,
    ) -> (lines: [String], range: Range<Int>)? {
        var moved = lines
        if upwards {
            guard range.lowerBound > 0 else {
                return nil
            }

            let above = moved.remove(at: range.lowerBound - 1)
            moved.insert(above, at: range.upperBound - 1)
            return (moved, range.lowerBound - 1 ..< range.upperBound - 1)
        }
        guard range.upperBound < lines.count else {
            return nil
        }

        let below = moved.remove(at: range.upperBound)
        moved.insert(below, at: range.lowerBound)
        return (moved, range.lowerBound + 1 ..< range.upperBound + 1)
    }

    /// What one Tab press indents by: a tab when the file already
    /// indents with tabs, otherwise spaces at the step the file's
    /// own levels share, and two spaces when the file says nothing
    /// usable.
    public static func indentationUnit(of lines: [String]) -> String {
        var step = 0
        for line in lines {
            if line.hasPrefix("\t") {
                return "\t"
            }

            let spaces = line.prefix { $0 == " " }.count
            // A whitespace-only line says nothing about indentation.
            if spaces > 0, spaces < line.count {
                step = greatestCommonDivisor(step, spaces)
            }
        }
        return String(repeating: " ", count: step > 1 ? step : Self.fallbackSpaces)
    }

    // MARK: Private

    /// What a file with no usable indentation of its own gets.
    private static let fallbackSpaces = 2

    private static func leadingWhitespace(of line: String) -> Substring {
        line.prefix { $0 == " " || $0 == "\t" }
    }

    private static func greatestCommonDivisor(_ first: Int, _ second: Int) -> Int {
        if second == 0 {
            first
        } else {
            greatestCommonDivisor(second, first % second)
        }
    }
}
