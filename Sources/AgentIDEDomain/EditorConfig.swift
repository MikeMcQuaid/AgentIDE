import Foundation

// MARK: - EditorConfigSettings

/// What a file's `.editorconfig` chain says about editing it. Every
/// property is optional: silence means the editor keeps its own
/// judgement (the file's own indentation, the app's save cleanup)
/// rather than inventing an answer.
public struct EditorConfigSettings: Equatable, Sendable {
    // MARK: Lifecycle

    /// Creates settings saying nothing, which every reader treats as
    /// "keep your own judgement".
    public init() {
        // Every property starts unspoken.
    }

    // MARK: Public

    /// Whether indentation is spaces or tabs.
    public enum IndentStyle: String, Sendable {
        // The case names are the spec's own words, which SwiftFormat
        // strips as redundant raw values.
        // swiftlint:disable explicit_enum_raw_value
        case space
        case tab
        // swiftlint:enable explicit_enum_raw_value
    }

    /// A yes-or-no property, which a file may also simply not
    /// mention: three states, so an optional boolean would be one
    /// question mark too many.
    public enum Preference: Sendable {
        case unspoken
        case enabled
        case disabled

        // MARK: Lifecycle

        /// The spec's booleans; anything else is unreadable and so
        /// says nothing.
        init(_ value: String) {
            switch value {
            case "true":
                self = .enabled

            case "false":
                self = .disabled

            default:
                self = .unspoken
            }
        }
    }

    public var indentStyle: IndentStyle?
    public var indentSize: Int?
    public var tabWidth: Int?
    public var trimsTrailingWhitespace: Preference = .unspoken
    public var insertsFinalNewline: Preference = .unspoken

    /// What one Tab press inserts, when the configuration says
    /// enough to know: a tab, or that many spaces. Nil leaves the
    /// editor reading the file's own shape.
    public var indentUnit: String? {
        switch indentStyle {
        case .tab:
            return "\t"

        case .space:
            guard let size = indentSize ?? tabWidth, size > 0 else {
                return nil
            }

            return String(repeating: " ", count: size)

        case nil:
            return nil
        }
    }
}

// MARK: - EditorConfigFile

/// One parsed `.editorconfig`, with the directory it governs.
public struct EditorConfigFile: Equatable, Sendable {
    // MARK: Public

    /// One `[glob]` section's properties, keys lowercased.
    public struct Section: Equatable, Sendable {
        public let glob: String
        public let properties: [String: String]
    }

    /// The name every one of these files has.
    public static let name = ".editorconfig"

    /// The directory holding the file, which its globs are relative
    /// to.
    public let directory: String

    /// Whether the search stops here rather than walking further up.
    public let isRoot: Bool

    public let sections: [Section]

    /// Parses one file's text. Anything unreadable is skipped rather
    /// than refused: a configuration file is advice, and a typo in
    /// it must not stop a file being edited.
    public static func parse(_ text: String, directory: String) -> Self {
        var declaresRoot = false
        var parsed = [Section]()
        var glob: String?
        var properties = [String: String]()
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix(";") {
                continue
            }
            if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
                if let glob {
                    parsed.append(Section(glob: glob, properties: properties))
                }
                glob = String(trimmed.dropFirst().dropLast())
                properties = [:]
                continue
            }
            guard let (key, value) = Self.pair(in: trimmed) else {
                continue
            }
            guard glob != nil else {
                // Before any section: only `root` means anything.
                declaresRoot = declaresRoot || (key == "root" && value == "true")
                continue
            }

            properties[key] = value
        }
        if let glob {
            parsed.append(Section(glob: glob, properties: properties))
        }
        return Self(directory: directory, isRoot: declaresRoot, sections: parsed)
    }

    // MARK: Private

    /// One `key = value` line, the key lowercased and the value
    /// lowercased too: every property this app reads is a keyword or
    /// a number, and the spec folds their case.
    private static func pair(in line: String) -> (key: String, value: String)? {
        guard let separator = line.firstIndex(of: "=") else {
            return nil
        }

        let key = line[..<separator].trimmingCharacters(in: .whitespaces).lowercased()
        let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces).lowercased()
        return key.isEmpty ? nil : (key, value)
    }
}

// MARK: - EditorConfig

/// Resolving a file's `.editorconfig` chain. The reading of the
/// files themselves belongs to the data layer; this is the rules.
public enum EditorConfig {
    // MARK: Public

    /// The settings for one file, given the `.editorconfig` files
    /// found walking up from it, nearest first. The walk stops at
    /// the first root, and nearer files and later sections win.
    public static func settings(forPath path: String, files: [EditorConfigFile]) -> EditorConfigSettings {
        var applicable = [EditorConfigFile]()
        for file in files {
            applicable.append(file)
            if file.isRoot {
                break
            }
        }
        var settings = EditorConfigSettings()
        // `indent_size = tab` defers to whatever tab width is in
        // force when everything has been read, which a later
        // section may still change.
        var defersToTabWidth = false
        for file in applicable.reversed() {
            let relative = Self.path(path, relativeTo: file.directory)
            for section in file.sections where matches(glob: section.glob, path: relative) {
                Self.apply(section.properties, to: &settings, defersToTabWidth: &defersToTabWidth)
            }
        }
        if defersToTabWidth {
            settings.indentSize = settings.tabWidth
        }
        return settings
    }

    // MARK: Private

    /// The file's path relative to a configuration's directory; a
    /// path outside it keeps its own shape, which no glob anchored
    /// to that directory then matches.
    private static func path(_ path: String, relativeTo directory: String) -> String {
        let base = directory.hasSuffix("/") ? directory : directory + "/"
        return path.hasPrefix(base) ? String(path.dropFirst(base.count)) : path
    }

    /// One section's properties over what earlier ones said. `unset`
    /// clears a property deliberately; a value that reads as nothing
    /// (a typo, a shape this app does not know) leaves the inherited
    /// one alone rather than quietly dropping it.
    private static func apply(
        _ properties: [String: String],
        to settings: inout EditorConfigSettings,
        defersToTabWidth: inout Bool,
    ) {
        for (key, value) in properties {
            let isUnset = value == "unset"
            switch key {
            case "indent_style":
                Self.set(&settings.indentStyle, EditorConfigSettings.IndentStyle(rawValue: value), isUnset)

            case "indent_size":
                defersToTabWidth = value == "tab"
                Self.set(&settings.indentSize, defersToTabWidth ? nil : Int(value), isUnset)

            case "tab_width":
                Self.set(&settings.tabWidth, Int(value), isUnset)

            case "trim_trailing_whitespace":
                Self.set(&settings.trimsTrailingWhitespace, EditorConfigSettings.Preference(value), isUnset)

            case "insert_final_newline":
                Self.set(&settings.insertsFinalNewline, EditorConfigSettings.Preference(value), isUnset)

            default:
                continue
            }
        }
    }

    /// Writes a read value, clears the property when the file said
    /// `unset`, and otherwise leaves it as inherited.
    private static func set<Value>(_ property: inout Value?, _ value: Value?, _ isUnset: Bool) {
        if isUnset {
            property = nil
        } else if let value {
            property = value
        }
    }

    /// The same for a preference, where unspoken is a value rather
    /// than an absence.
    private static func set(
        _ property: inout EditorConfigSettings.Preference,
        _ value: EditorConfigSettings.Preference,
        _ isUnset: Bool,
    ) {
        if isUnset {
            property = .unspoken
        } else if value != .unspoken {
            property = value
        }
    }
}
