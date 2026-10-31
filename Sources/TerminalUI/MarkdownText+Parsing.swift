import Foundation
import SanductorData
import SwiftUI
import Textual

extension MarkdownText {
    static func content(_ text: String) -> AttributedString {
        contentCache.value(for: text) { raw in
            let source = strippingHTML(raw)
            let matter = frontMatter(in: source)
            let body = matter?.body ?? source
            var content = (try? AttributedStringMarkdownParser.markdown().attributedString(for: body))
                ?? AttributedString(body)
            for run in content.runs {
                if let url = run.imageURL, url.scheme == nil, url.host == nil, url.path.hasPrefix("/") {
                    content[run.range].imageURL = URL(filePath: url.path)
                }
            }
            var result = matter.map { frontMatterTable($0.fields) } ?? AttributedString()
            result.append(adapted(content))
            return result
        }
    }

    private static func frontMatterTable(_ fields: [(key: String, value: String)]) -> AttributedString {
        var result = AttributedString()
        // Metadata identities stay separate from parsed blocks.
        var identity = -1
        let table = PresentationIntent(
            .table(columns: [.init(alignment: .left), .init(alignment: .left)]), identity: identity,
        )
        for (index, field) in ([(key: "Field", value: "Value")] + fields).enumerated() {
            identity -= 1
            let row = PresentationIntent(
                index == 0 ? .tableHeaderRow : .tableRow(rowIndex: index),
                identity: identity,
                parent: table,
            )
            for (column, value) in [field.key, field.value].enumerated() {
                identity -= 1
                var cell = AttributedString(value.isEmpty ? " " : value)
                cell.presentationIntent = PresentationIntent(
                    .tableCell(columnIndex: column), identity: identity, parent: row,
                )
                if column == 0 {
                    cell.inlinePresentationIntent = .stronglyEmphasized
                }
                result.append(cell)
            }
        }
        return result
    }

    private static func adapted(_ original: AttributedString) -> AttributedString {
        var content = original
        var containers = Set<Int>()
        var replacements = [(Range<AttributedString.Index>, AttributedString)]()
        for (intent, range) in original.runs[\.presentationIntent] {
            guard let components = intent?.components, let container = components.dropFirst().first else {
                continue
            }

            let first = containers.insert(container.identity).inserted
            containers.formUnion(components.map(\.identity))
            guard first, components.first?.kind == .paragraph,
                  original[range].runs.first?.inlinePresentationIntent == nil
            else {
                continue
            }

            let source = String(original[range].characters)
            if case .listItem = container.kind {
                for (marker, symbol) in [("[ ]", "☐"), ("[x]", "☑"), ("[X]", "☑")]
                    where source == marker || source.hasPrefix(marker + " ")
                {
                    let end = original.characters.index(range.lowerBound, offsetBy: marker.count)
                    var replacement = AttributedString(symbol)
                    replacement.presentationIntent = intent
                    replacements.append((range.lowerBound ..< end, replacement))
                }
            } else if container.kind == .blockQuote {
                let alerts: [(String, Color)] = [
                    ("Note", .blue), ("Tip", .green), ("Important", .purple), ("Warning", .orange), ("Caution", .red),
                ]
                for (title, colour) in alerts {
                    let marker = "[!" + title.uppercased() + "]"
                    guard source == marker || source.hasPrefix(marker + " ") else {
                        continue
                    }

                    let end = original.characters.index(range.lowerBound, offsetBy: min(source.count, marker.count + 1))
                    var replacement = AttributedString(title + "\n")
                    replacement.presentationIntent = intent
                    replacement.inlinePresentationIntent = .stronglyEmphasized
                    replacement.foregroundColor = colour
                    replacements.append((range.lowerBound ..< end, replacement))
                }
            }
        }
        for (range, replacement) in replacements.reversed() {
            content.replaceSubrange(range, with: replacement)
        }
        return content
    }

    /// YAML front matter and what follows it, when the text opens
    /// with a `---` line closed by another and every line between
    /// is a `key: value` or continues the one before. Values are
    /// kept as written, quotes off; a list or a nested map reads as
    /// its lines joined, since a table cell has one line to give.
    static func frontMatter(in text: String) -> (fields: [(key: String, value: String)], body: String)? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.first == "---", let close = lines.dropFirst().firstIndex(of: "---") else {
            return nil
        }

        var fields = [(key: String, value: String)]()
        for line in lines[1 ..< close] {
            if line.first?.isWhitespace == true || line.hasPrefix("- "), fields.isEmpty == false {
                let more = line.trimmingCharacters(in: .whitespaces)
                let last = fields.removeLast()
                fields.append((last.key, last.value.isEmpty ? more : last.value + " " + more))
                continue
            }
            guard let colon = line.firstIndex(of: ":"), colon != line.startIndex,
                  line[..<colon].contains(where: \.isWhitespace) == false
            else {
                return nil
            }

            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            fields.append((String(line[..<colon]), unquoted(value)))
        }
        guard fields.isEmpty == false else {
            return nil
        }

        return (fields, lines[(close + 1)...].joined(separator: "\n"))
    }

    /// A value without the quotes YAML allows around it.
    private static func unquoted(_ value: String) -> String {
        for quote in ["\"", "'"] where value.count > 1 && value.hasPrefix(quote) && value.hasSuffix(quote) {
            return String(value.dropFirst().dropLast())
        }
        return value
    }

    /// Maps common HTML formatting while preserving literal code.
    static func strippingHTML(_ text: String) -> String {
        (try? MarkdownHTML(text).markdown) ?? text
    }
}
