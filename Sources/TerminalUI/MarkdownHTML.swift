import Foundation
import SwiftSoup

/// HTML structure around Markdown, never an executable document.
struct MarkdownHTML {
    // MARK: Lifecycle

    init(_ source: String) throws {
        protected = try MarkdownHTMLCode(source)
        document = try SwiftSoup.parseBodyFragment(protected.source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("[//]: #") == false }
            .joined(separator: "\n"))
        document.outputSettings().prettyPrint(pretty: false)
    }

    // MARK: Internal

    var markdown: String {
        protected.restore(render(document.body()?.getChildNodes() ?? []))
    }

    var chunks: [MarkdownText.Chunk] {
        var result = [MarkdownText.Chunk]()
        var plain = ""
        for node in disclosureNodes(document.body()?.getChildNodes() ?? []) {
            guard let element = node as? Element, element.tagName() == "details" else {
                plain += (try? node.outerHtml()) ?? ""
                continue
            }

            if plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                result.append(MarkdownText.Chunk(text: protected.restore(plain), detailsSummary: nil))
            }
            plain = ""
            let children = element.getChildNodes()
            let summary = children.first { ($0 as? Element)?.tagName() == "summary" }
            let title = protected.restore(render(summary?.getChildNodes() ?? []))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let body = children.filter { $0 !== summary }.map { (try? $0.outerHtml()) ?? "" }.joined()
            result.append(MarkdownText.Chunk(
                text: protected.restore(body), detailsSummary: title.isEmpty ? "Details" : title,
            ))
        }
        if plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            result.append(MarkdownText.Chunk(text: protected.restore(plain), detailsSummary: nil))
        }
        return result
    }

    // MARK: Private

    private static let fenceLength = 3

    private let protected: MarkdownHTMLCode
    private let document: SwiftSoup.Document

    private func disclosureNodes(_ nodes: [Node]) -> [Node] {
        nodes.flatMap { node in
            if let element = node as? Element, ["blockquote", "div", "section"].contains(element.tagName()),
               (try? element.select("details").isEmpty()) == false
            {
                return disclosureNodes(element.getChildNodes())
            }
            return [node]
        }
    }

    private func render(_ nodes: [Node]) -> String {
        nodes.map { node in
            if let text = node as? TextNode {
                return text.getWholeText()
            }
            guard let element = node as? Element else {
                return ""
            }

            return render(element)
        }
        .joined()
    }

    private func render(_ element: Element) -> String {
        let body = render(element.getChildNodes())
        switch element.tagName() {
        case "iframe",
             "object",
             "script",
             "style":
            return ""

        case "pre":
            let code = element.getChildNodes().map { literalText($0) }.joined()
            let fence = String(
                repeating: "`",
                count: max(Self.fenceLength, (code.matches(of: /`+/).map(\.output.count).max() ?? 0) + 1),
            )
            return "\n\n" + fence + "\n" + code + "\n" + fence + "\n\n"

        case "br":
            return "  \n"

        case "hr":
            return "\n\n---\n\n"

        case "div",
             "ol",
             "p",
             "section",
             "ul":
            return "\n\n" + body + "\n\n"

        case "li":
            return "\n- " + body.trimmingCharacters(in: .whitespacesAndNewlines)

        case "blockquote":
            return "\n\n" + body.trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .lazy
                .map { "> " + $0 }
                .joined(separator: "\n") + "\n\n"

        default:
            return renderInline(element, body: body)
        }
    }

    private func renderInline(_ element: Element, body: String) -> String {
        switch element.tagName() {
        case "b",
             "strong":
            return "**" + body + "**"

        case "em",
             "i":
            return "*" + body + "*"

        case "del",
             "s",
             "strike":
            return "~~" + body + "~~"

        case "code",
             "kbd":
            let ticks = String(repeating: "`", count: (body.matches(of: /`+/).map(\.output.count).max() ?? 0) + 1)
            return ticks + body + ticks

        case "a":
            let href = (try? element.attr("href")) ?? ""
            return href.isEmpty ? body : "[" + body + "](" + href + ")"

        case "img":
            return (try? element.attr("alt")) ?? ""

        case "summary":
            return body + "\n\n"

        default:
            return body
        }
    }

    private func literalText(_ node: Node) -> String {
        if let text = node as? TextNode {
            return text.getWholeText()
        }
        return node.getChildNodes().map { literalText($0) }.joined()
    }
}
