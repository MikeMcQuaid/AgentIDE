import Foundation
import SwiftSoup

/// HTML structure around Markdown, never an executable document.
public struct MarkdownHTML {
    // MARK: Lifecycle

    /// Parses HTML while keeping embedded Markdown code intact.
    public init(_ source: String, compactReview: Bool = false) throws {
        self.compactReview = compactReview
        protected = try MarkdownHTMLCode(source)
        document = try SwiftSoup.parseBodyFragment(protected.source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("[//]: #") == false }
            .joined(separator: "\n"))
        document.outputSettings().prettyPrint(pretty: false)
        if compactReview {
            for details in try document.select("details") {
                let summary = try details.select("summary").first()?.text().lowercased() ?? ""
                if [
                    "supported by", "analysis", "investigation", "reasoning", "learnings", "review info",
                    "usage-based", "share", "ai agents",
                ].contains(where: summary.contains) {
                    try details.remove()
                } else {
                    try details.select("summary").remove()
                }
            }
            try document.select("picture, img, source").remove()
        }
    }

    // MARK: Public

    /// Markdown with an optional disclosure title.
    public struct Chunk {
        // MARK: Lifecycle

        /// Creates a renderable section.
        public init(text: String, detailsSummary: String?) {
            self.text = text
            self.detailsSummary = detailsSummary
        }

        // MARK: Public

        /// The section body.
        public let text: String
        /// The disclosure label, or nil for ordinary text.
        public let detailsSummary: String?
    }

    /// Safe Markdown with HTML wrappers removed.
    public var markdown: String {
        var text = render(document.body()?.getChildNodes() ?? [])
        if compactReview {
            text = text.replacingOccurrences(
                of: #"(?m)^[ \t]*(?:\*\*|_)[ \t]*(?:Critical|Major|Minor|Trivial)(?:\*\*|_)[^\n]*\n*"#,
                with: "",
                options: .regularExpression,
            )
            .replacingOccurrences(of: #"\n[ \t]*\n(?:[ \t]*\n)+"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .newlines)
        }
        return protected.restore(text)
    }

    /// Top-level sections, retaining disclosure boundaries.
    public var chunks: [Chunk] {
        var result = [Chunk]()
        var plain = [Node]()
        for node in disclosureNodes(document.body()?.getChildNodes() ?? []) {
            guard let element = node as? Element, element.tagName() == "details" else {
                plain.append(node)
                continue
            }

            if render(plain).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                result.append(Chunk(
                    text: protected.restore(plain.map { (try? $0.outerHtml()) ?? "" }.joined()), detailsSummary: nil,
                ))
            }
            plain = []
            let children = element.getChildNodes()
            let summary = children.first { ($0 as? Element)?.tagName() == "summary" }
            let titleSource = render(summary?.getChildNodes() ?? [])
            let title = protected.restore((try? MarkdownHTMLCode(titleSource))
                .map { $0.restore($0.source.replacing("**", with: "")) } ?? titleSource)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let body = children.filter { $0 !== summary }.map { (try? $0.outerHtml()) ?? "" }.joined()
            result.append(Chunk(
                text: protected.restore(body), detailsSummary: title.isEmpty ? "Details" : title,
            ))
        }
        if render(plain).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            result.append(Chunk(
                text: protected.restore(plain.map { (try? $0.outerHtml()) ?? "" }.joined()), detailsSummary: nil,
            ))
        }
        return result
    }

    // MARK: Private

    private static let fenceLength = 3
    private static let maximumListStart = 999_999_999

    private let compactReview: Bool
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
             "p",
             "section":
            return "\n\n" + body + "\n\n"

        case "ol",
             "ul":
            let start = Int((try? element.attr("start")) ?? "")
                .flatMap { (0 ... Self.maximumListStart).contains($0) ? $0 : nil } ?? 1
            return "\n\n" + element.children()
                .filter { $0.tagName() == "li" }
                .enumerated()
                .lazy
                .map { index, item in
                    let marker = element.tagName() == "ol" ? String(start + index) + ". " : "- "
                    return marker + render(item.getChildNodes())
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacing("\n", with: "\n" + String(repeating: " ", count: marker.count))
                }
                .joined(separator: "\n") + "\n\n"

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
            return wrapped(body, in: "**")

        case "em",
             "i":
            return wrapped(body, in: "*")

        case "del",
             "s",
             "strike":
            return wrapped(body, in: "~~")

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

    private func wrapped(_ body: String, in marker: String) -> String {
        guard let start = body.firstIndex(where: { $0.isWhitespace == false }),
              let end = body.lastIndex(where: { $0.isWhitespace == false })
        else {
            return body
        }

        return body[..<start] + marker + body[start ... end] + marker + body[body.index(after: end)...]
    }

    private func literalText(_ node: Node) -> String {
        if let text = node as? TextNode {
            return text.getWholeText()
        }
        return node.getChildNodes().map { literalText($0) }.joined()
    }
}
