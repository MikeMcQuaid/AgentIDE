import Foundation

/// What the app knows about each language by name: which files are
/// which, and what each calls its own words. tree-sitter does the
/// real parsing where a grammar is loaded; these carry the rest,
/// and carry every language when a grammar fails to load.
extension SyntaxLanguage {
    /// Every extension the app claims, mapped to what parses it. A
    /// table rather than a switch: it is data, and it grows.
    static let byExtension: [String: Self] = [
        "swift": .swift,
        "gemspec": .ruby, "jbuilder": .ruby, "podspec": .ruby, "rake": .ruby, "rb": .ruby,
        "ru": .ruby, "thor": .ruby,
        "bash": .shell, "fish": .shell, "ksh": .shell, "sh": .shell, "zsh": .shell,
        "py": .python, "pyi": .python, "pyw": .python,
        "geojson": .json, "har": .json, "json": .json, "jsonc": .json, "webmanifest": .json,
        "cjs": .typescript, "cts": .typescript, "js": .typescript, "jsx": .typescript,
        "mjs": .typescript, "mts": .typescript, "ts": .typescript, "tsx": .typescript,
        "c": .cSource, "h": .cSource,
        "cc": .cpp, "cpp": .cpp, "cxx": .cpp, "hh": .cpp, "hpp": .cpp, "hxx": .cpp, "mm": .cpp,
        "go": .golang,
        "rs": .rust,
        "java": .java,
        "php": .php,
        "htm": .html, "html": .html, "xhtml": .html,
        "css": .css, "sass": .css, "scss": .css,
        "ejs": .erb, "erb": .erb,
        "yaml": .yaml, "yml": .yaml,
        "markdown": .markdown, "md": .markdown, "mdown": .markdown, "mdx": .markdown,
        "cfg": .config, "conf": .config, "gitconfig": .config, "ini": .config,
        "properties": .config, "toml": .config,
    ]

    /// Extensions worth no highlighting at all.
    static let binaryExtensions: Set<String> = [
        "a", "bin", "bmp", "class", "dmg", "dylib", "exe", "gif", "gz", "heic", "ico", "icns",
        "jar", "jpeg", "jpg", "mov", "mp3", "mp4", "o", "otf", "pdf", "png", "pyc", "so", "svg",
        "tar", "tiff", "ttf", "wav", "webp", "woff", "woff2", "zip",
    ]

    /// Shell configuration carrying no extension of its own.
    static let shellNames: Set<String> = [
        ".bash_profile", ".bashrc", ".envrc", ".profile", ".zprofile", ".zshenv", ".zshrc",
    ]

    /// Dotfiles that are keys and sections rather than a language.
    static let configNames: Set<String> = [
        ".editorconfig", ".env", ".gitattributes", ".gitconfig", ".gitignore", ".gitmodules",
        ".shellcheckrc", ".npmrc", ".curlrc", ".inputrc", ".netrc",
    ]

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

        case .json:
            ["true", "false", "null"]

        case .typescript:
            [
                "const", "let", "var", "function", "return", "if", "else", "for", "while", "do",
                "switch", "case", "default", "break", "continue", "class", "interface", "type",
                "enum", "extends", "implements", "import", "export", "from", "as", "new", "this",
                "null", "undefined", "true", "false", "async", "await", "try", "catch", "finally",
                "throw", "typeof", "instanceof", "in", "of", "readonly", "public", "private",
                "protected", "static", "abstract", "namespace", "declare", "keyof", "never",
                "unknown", "any", "void", "string", "number", "boolean",
            ]

        case .dockerfile:
            [
                "FROM", "RUN", "CMD", "LABEL", "EXPOSE", "ENV", "ADD", "COPY", "ENTRYPOINT",
                "VOLUME", "USER", "WORKDIR", "ARG", "ONBUILD", "STOPSIGNAL", "HEALTHCHECK",
                "SHELL", "AS",
            ]

        case .yaml:
            ["true", "false", "null", "yes", "no", "on", "off"]

        case .cpp,
             .cSource:
            [
                "if", "else", "for", "while", "do", "switch", "case", "default", "break",
                "continue", "return", "struct", "union", "enum", "typedef", "const", "static",
                "void", "int", "char", "float", "double", "long", "short", "unsigned", "signed",
                "sizeof", "include", "define", "class", "public", "private", "protected",
                "namespace", "template", "typename", "virtual", "override", "new", "delete",
                "nullptr", "true", "false", "auto", "using", "constexpr", "noexcept",
            ]

        case .golang:
            [
                "package", "import", "func", "var", "const", "type", "struct", "interface",
                "map", "chan", "go", "defer", "if", "else", "for", "range", "switch", "case",
                "default", "break", "continue", "return", "select", "fallthrough", "nil",
                "true", "false", "make", "new", "len", "cap", "append", "error",
            ]

        case .rust:
            [
                "fn", "let", "mut", "const", "static", "struct", "enum", "trait", "impl", "for",
                "while", "loop", "if", "else", "match", "return", "use", "mod", "pub", "crate",
                "self", "super", "where", "async", "await", "move", "ref", "dyn", "unsafe",
                "true", "false", "Some", "None", "Ok", "Err", "as", "in", "break", "continue",
            ]

        case .java:
            [
                "public", "private", "protected", "class", "interface", "enum", "extends",
                "implements", "package", "import", "static", "final", "abstract", "void", "new",
                "return", "if", "else", "for", "while", "do", "switch", "case", "default",
                "break", "continue", "try", "catch", "finally", "throw", "throws", "this",
                "super", "null", "true", "false", "instanceof", "synchronized", "record", "var",
            ]

        case .php:
            [
                "function", "class", "interface", "trait", "extends", "implements", "namespace",
                "use", "public", "private", "protected", "static", "const", "return", "if",
                "else", "elseif", "foreach", "for", "while", "do", "switch", "case", "default",
                "break", "continue", "try", "catch", "finally", "throw", "new", "echo", "print",
                "null", "true", "false", "array", "isset", "unset", "require", "include",
            ]

        case .css:
            [
                "important", "media", "supports", "keyframes", "import", "charset", "inherit",
                "initial", "unset", "auto", "none", "block", "flex", "grid", "absolute",
                "relative", "fixed", "sticky", "hidden", "visible", "solid", "dashed", "dotted",
            ]

        case .erb,
             .html:
            [
                "html", "head", "body", "div", "span", "script", "style", "link", "meta", "title",
                "class", "id", "href", "src", "alt", "type", "section", "article", "header",
                "footer", "nav", "main", "form", "input", "button", "label", "table", "tr", "td",
            ]

        case .config:
            ["true", "false", "yes", "no", "on", "off", "null", "none"]

        case .gitRebaseTodo:
            Self.rebaseCommands

        case .generic,
             .gitMessage,
             .markdown,
             .regex:
            []
        }
    }
}
