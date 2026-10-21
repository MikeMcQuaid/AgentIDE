import Foundation

/// Block identities distinguish repeated paragraphs and nested lists.
enum MarkdownTestSupport {
    static func kinds(_ content: AttributedString) -> [PresentationIntent.Kind] {
        var identities = Set<Int>()
        return content.runs
            .flatMap { $0.presentationIntent?.components ?? [] }
            .filter { identities.insert($0.identity).inserted }
            .map(\.kind)
    }
}
