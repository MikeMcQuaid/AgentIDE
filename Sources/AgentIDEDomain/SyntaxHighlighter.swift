// MARK: - SyntaxToken

/// A run of characters within one source line, classified for
/// colouring.
public struct SyntaxToken: Hashable, Sendable {
    // MARK: Lifecycle

    /// Creates a token.
    public init(kind: Kind, text: String) {
        self.kind = kind
        self.text = text
    }

    // MARK: Public

    /// The colour class of a token.
    public enum Kind: Hashable, Sendable {
        /// A language keyword.
        case keyword
        /// A string literal, including its quotes.
        case string
        /// A comment to the end of the line.
        case comment
        /// A numeric literal.
        case number
        /// Anything else.
        case plain
    }

    /// The colour class.
    public let kind: Kind

    /// The token's exact characters; concatenating a line's tokens
    /// reproduces the line.
    public let text: String
}

// MARK: - SyntaxLanguage

/// The languages the highlighter understands.
public enum SyntaxLanguage: Hashable, Sendable {
    case swift
    case ruby
    case shell
    case python
    case yaml
    case markdown

    // MARK: Public

    /// The language for a file path, judged by extension, nil when
    /// unknown.
    public static func language(forPath path: String) -> Self? {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        let extensionName = name.split(separator: ".").last.map(String.init) ?? ""
        switch extensionName {
        case "swift":
            return .swift

        case "gemspec",
             "rake",
             "rb":
            return .ruby

        case "bash",
             "sh",
             "zsh":
            return .shell

        case "py":
            return .python

        case "yaml",
             "yml":
            return .yaml

        case "markdown",
             "md":
            return .markdown

        default:
            return name == "Gemfile" || name == "Rakefile" || name == "Brewfile" ? .ruby : nil
        }
    }

    // MARK: Internal

    /// The line-comment introducer, empty for languages without one.
    var commentPrefix: String {
        switch self {
        case .swift:
            "//"

        case .python,
             .ruby,
             .shell,
             .yaml:
            "#"

        case .markdown:
            ""
        }
    }

    /// The language's keywords.
    var keywords: Set<String> {
        switch self {
        case .swift:
            [
                "func", "let", "var", "if", "else", "guard", "return", "struct", "class", "enum",
                "protocol", "extension", "import", "public", "private", "internal", "static",
                "case", "switch", "for", "while", "in", "throws", "throw", "try", "await",
                "async", "init", "deinit", "self", "nil", "true", "false", "where", "defer",
                "do", "catch", "some", "any", "actor", "mutating", "final", "override", "break",
                "continue", "default", "typealias", "associatedtype", "package",
            ]

        case .ruby:
            [
                "def", "end", "if", "elsif", "else", "unless", "case", "when", "while", "until",
                "for", "in", "do", "return", "class", "module", "self", "nil", "true", "false",
                "and", "or", "not", "then", "yield", "begin", "rescue", "ensure", "raise",
                "require", "require_relative", "attr_reader", "attr_writer", "attr_accessor",
                "private", "public", "protected", "new", "lambda", "proc", "puts", "block_given?",
            ]

        case .shell:
            [
                "if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done",
                "case", "esac", "function", "return", "exit", "local", "export", "readonly",
                "shift", "source", "set", "unset", "trap", "echo", "printf", "read", "eval",
                "exec", "true", "false", "in",
            ]

        case .python:
            [
                "def", "class", "if", "elif", "else", "for", "while", "in", "return", "import",
                "from", "as", "with", "try", "except", "finally", "raise", "pass", "break",
                "continue", "lambda", "yield", "global", "nonlocal", "assert", "del", "not",
                "and", "or", "is", "None", "True", "False", "async", "await", "match", "case",
            ]

        case .yaml:
            ["true", "false", "null", "yes", "no", "on", "off"]

        case .markdown:
            []
        }
    }
}

// MARK: - SyntaxHighlighter

/// A single-line tokenizer for review diffs: strings, line comments,
/// numbers and keywords. Lines are highlighted independently, so
/// multi-line constructs (block comments, heredocs) fall back to
/// plain text.
public enum SyntaxHighlighter {
    // MARK: Public

    /// Splits one line into coloured tokens; concatenating the token
    /// texts reproduces the line.
    public static func highlight(line: String, language: SyntaxLanguage) -> [SyntaxToken] {
        if language == .markdown {
            return markdownTokens(line: line)
        }

        var tokens = [SyntaxToken]()
        var plain = ""
        let characters = Array(line)
        var index = 0

        func flushPlain() {
            guard plain.isEmpty == false else {
                return
            }

            tokens.append(SyntaxToken(kind: .plain, text: plain))
            plain = ""
        }

        let commentPrefix = language.commentPrefix
        while index < characters.count {
            let character = characters[index]
            if commentPrefix.isEmpty == false, matches(characters, at: index, prefix: commentPrefix) {
                flushPlain()
                tokens.append(SyntaxToken(kind: .comment, text: String(characters[index...])))
                return merge(tokens)
            }
            if character == "\"" || character == "'" {
                flushPlain()
                let literal = stringLiteral(characters, from: &index, quote: character)
                tokens.append(SyntaxToken(kind: .string, text: literal))
                continue
            }
            if character.isNumber, isWordBoundary(characters, before: index) {
                flushPlain()
                let number = run(characters, from: &index) { $0.isNumber || $0 == "." || $0 == "_" }
                tokens.append(SyntaxToken(kind: .number, text: number))
                continue
            }
            if isWordCharacter(character), isWordBoundary(characters, before: index) {
                let word = run(characters, from: &index) { isWordCharacter($0) || $0 == "?" }
                if language.keywords.contains(word) {
                    flushPlain()
                    tokens.append(SyntaxToken(kind: .keyword, text: word))
                } else {
                    plain += word
                }
                continue
            }
            plain.append(character)
            index += 1
        }
        flushPlain()
        return merge(tokens)
    }

    // MARK: Private

    /// Markdown gets structural colouring: headings whole-line, and
    /// inline code spans as strings.
    private static func markdownTokens(line: String) -> [SyntaxToken] {
        if line.drop(while: { $0 == " " || $0 == "\t" }).first == "#" {
            return [SyntaxToken(kind: .keyword, text: line)]
        }

        var tokens = [SyntaxToken]()
        var run = ""
        var inCode = false
        for character in line {
            if character == "`" {
                if inCode {
                    tokens.append(SyntaxToken(kind: .string, text: run + "`"))
                } else if run.isEmpty == false {
                    tokens.append(SyntaxToken(kind: .plain, text: run))
                }
                run = inCode ? "" : "`"
                inCode.toggle()
                continue
            }
            run.append(character)
        }
        if run.isEmpty == false {
            tokens.append(SyntaxToken(kind: inCode ? .string : .plain, text: run))
        }
        return tokens
    }

    private static func matches(_ characters: [Character], at index: Int, prefix: String) -> Bool {
        let prefixCharacters = Array(prefix)
        guard index + prefixCharacters.count <= characters.count else {
            return false
        }

        return Array(characters[index ..< index + prefixCharacters.count]) == prefixCharacters
    }

    private static func stringLiteral(
        _ characters: [Character],
        from index: inout Int,
        quote: Character,
    ) -> String {
        var literal = String(characters[index])
        index += 1
        while index < characters.count {
            let character = characters[index]
            literal.append(character)
            index += 1
            if character == "\\", index < characters.count {
                literal.append(characters[index])
                index += 1
            } else if character == quote {
                break
            }
        }
        return literal
    }

    private static func run(
        _ characters: [Character],
        from index: inout Int,
        while predicate: (Character) -> Bool,
    ) -> String {
        var text = ""
        while index < characters.count, predicate(characters[index]) {
            text.append(characters[index])
            index += 1
        }
        return text
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    private static func isWordBoundary(_ characters: [Character], before index: Int) -> Bool {
        index == 0 || isWordCharacter(characters[index - 1]) == false
    }

    private static func merge(_ tokens: [SyntaxToken]) -> [SyntaxToken] {
        tokens.reduce(into: [SyntaxToken]()) { merged, token in
            if let last = merged.last, last.kind == token.kind {
                merged[merged.count - 1] = SyntaxToken(kind: last.kind, text: last.text + token.text)
            } else {
                merged.append(token)
            }
        }
    }
}
