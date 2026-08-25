import AgentIDEDomain
import Foundation
import SwiftTreeSitter
import TreeSitterBash
import TreeSitterC
import TreeSitterCPP
import TreeSitterCSS
import TreeSitterEmbeddedTemplate
import TreeSitterGo
import TreeSitterHTML
import TreeSitterJava
import TreeSitterJSON
import TreeSitterPHP
import TreeSitterPython
import TreeSitterRegex
import TreeSitterRuby
import TreeSitterRust
import TreeSitterSwift
import TreeSitterTypeScript

/// Syntax highlighting through tree-sitter grammars, the same parsers
/// editors standardise on. The pure-Swift tokenizer in the Domain
/// remains the fallback for text tree-sitter cannot classify.
public enum CodeHighlighter {
    // MARK: Public

    /// The coloured tokens of one line; concatenating the token texts
    /// reproduces the line.
    public static func tokens(for line: String, language: SyntaxLanguage?) -> [SyntaxToken] {
        guard let language else {
            return [SyntaxToken(kind: .plain, text: line)]
        }
        guard let classified = classifiedRanges(in: line, language: language), classified.isEmpty == false else {
            return SyntaxHighlighter.highlight(line: line, language: language)
        }

        // Capture ranges are UTF-16 offsets, so NSString arithmetic is
        // the correct interop here, not String.
        // swiftlint:disable:next legacy_objc_type
        let content = line as NSString
        var kinds = [SyntaxToken.Kind](repeating: .plain, count: content.length)
        for (range, kind) in classified {
            for offset in range.location ..< min(NSMaxRange(range), content.length) {
                kinds[offset] = kind
            }
        }

        var tokens = [SyntaxToken]()
        var start = 0
        for index in 1 ... content.length where index == content.length || kinds[index] != kinds[start] {
            let range = NSRange(location: start, length: index - start)
            tokens.append(SyntaxToken(kind: kinds[start], text: content.substring(with: range)))
            start = index
        }
        return tokens
    }

    /// The classified ranges of a whole document, UTF-16 based, for
    /// attributed editors: tree-sitter when the grammar loaded, the
    /// line tokenizer otherwise, so every surface shares one backend.
    public static func documentRanges(
        in text: String,
        language: SyntaxLanguage,
    ) -> [(range: NSRange, kind: SyntaxToken.Kind)] {
        if let classified = classifiedRanges(in: text, language: language) {
            return classified
        }

        var results = [(range: NSRange, kind: SyntaxToken.Kind)]()
        var location = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var offset = location
            for token in SyntaxHighlighter.highlight(line: String(line), language: language) {
                // swiftlint:disable:next legacy_objc_type
                let length = (token.text as NSString).length
                if token.kind != .plain {
                    results.append((NSRange(location: offset, length: length), token.kind))
                }
                offset += length
            }
            // swiftlint:disable:next legacy_objc_type
            location += (String(line) as NSString).length + 1
        }
        return results
    }

    // nil means no grammar loaded, which callers treat differently
    // from a successful parse with nothing to colour.
    // swiftlint:disable discouraged_optional_collection

    /// The classified ranges of a whole document, UTF-16 based, for
    /// attributed editors; nil when the language has no grammar.
    public static func classifiedRanges(
        in text: String,
        language: SyntaxLanguage,
    ) -> [(range: NSRange, kind: SyntaxToken.Kind)]? {
        // swiftlint:enable discouraged_optional_collection
        guard text.isEmpty == false,
              let configuration = configurations[language],
              let query = configuration.queries[.highlights]
        else {
            return nil
        }

        let parser = Parser()
        guard (try? parser.setLanguage(configuration.language)) != nil,
              let tree = parser.parse(text)
        else {
            return nil
        }

        let cursor = query.execute(in: tree)
        var results = [(range: NSRange, kind: SyntaxToken.Kind)]()
        while let match = cursor.next() {
            for capture in match.captures {
                guard let kind = kind(forCaptureName: capture.name ?? "") else {
                    continue
                }

                results.append((capture.node.range, kind))
            }
        }
        return results
    }

    // MARK: Private

    /// Grammars are loaded once; a failed load leaves the language on
    /// the fallback tokenizer.
    private static let configurations: [SyntaxLanguage: LanguageConfiguration] = {
        var loaded = [SyntaxLanguage: LanguageConfiguration]()
        loaded[.swift] = configuration(tree_sitter_swift(), name: "Swift")
        loaded[.ruby] = configuration(tree_sitter_ruby(), name: "Ruby")
        loaded[.shell] = configuration(tree_sitter_bash(), name: "Bash")
        loaded[.python] = configuration(tree_sitter_python(), name: "Python")
        loaded[.json] = configuration(tree_sitter_json(), name: "JSON")
        loaded[.typescript] = configuration(tree_sitter_typescript(), name: "TypeScript")
        loaded[.cSource] = configuration(tree_sitter_c(), name: "C")
        loaded[.cpp] = configuration(tree_sitter_cpp(), name: "CPP")
        loaded[.golang] = configuration(tree_sitter_go(), name: "Go")
        loaded[.rust] = configuration(tree_sitter_rust(), name: "Rust")
        loaded[.java] = configuration(tree_sitter_java(), name: "Java")
        loaded[.php] = configuration(tree_sitter_php(), name: "PHP")
        loaded[.html] = configuration(tree_sitter_html(), name: "HTML")
        loaded[.css] = configuration(tree_sitter_css(), name: "CSS")
        loaded[.regex] = configuration(tree_sitter_regex(), name: "Regex")
        loaded[.erb] = configuration(tree_sitter_embedded_template(), name: "EmbeddedTemplate")
        return loaded
    }()

    /// Places SwiftPM or Xcode may have put grammar resource bundles.
    /// `Bundle.main` lies under test runners, so the anchor is a class
    /// linked into whichever image carries this code: the app, or a
    /// test bundle.
    private static let bundleContainers: [URL] = {
        let anchor = Bundle(for: TerminalRepresentable.Coordinator.self)
        var containers = [URL]()
        if let resources = anchor.resourceURL {
            containers.append(resources)
        }
        containers.append(anchor.bundleURL.deletingLastPathComponent())
        if let resources = Bundle.main.resourceURL {
            containers.append(resources)
        }
        return containers
    }()

    /// Loads a grammar and its bundled highlight queries. SwiftPM's
    /// command line builds lay resource bundles out flat while Xcode
    /// nests them under `Contents/Resources`, so both are tried
    /// before the library's own heuristics.
    private static func configuration(_ grammar: OpaquePointer, name: String) -> LanguageConfiguration? {
        let bundleName = "TreeSitter\(name)_TreeSitter\(name).bundle"
        for container in bundleContainers {
            let bundle = container.appendingPathComponent(bundleName)
            let layouts = [
                bundle.appendingPathComponent("queries"),
                bundle.appendingPathComponent("Contents/Resources/queries"),
            ]
            for queries in layouts where FileManager.default.fileExists(atPath: queries.path) {
                if let configuration = try? LanguageConfiguration(grammar, name: name, queriesURL: queries) {
                    return configuration
                }
            }
        }
        return try? LanguageConfiguration(grammar, name: name)
    }

    /// Maps tree-sitter capture names onto the app's colour classes.
    private static func kind(forCaptureName name: String) -> SyntaxToken.Kind? {
        let root = name.split(separator: ".").first.map(String.init) ?? name
        switch root {
        case "boolean",
             "conditional",
             "exception",
             "include",
             "keyword",
             "operator",
             "repeat":
            return .keyword

        case "string",
             "text":
            return .string

        case "comment":
            return .comment

        case "float",
             "integer",
             "number":
            return .number

        default:
            return nil
        }
    }
}
