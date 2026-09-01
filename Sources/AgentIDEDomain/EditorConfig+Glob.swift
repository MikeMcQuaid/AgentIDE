/// Matching a path against an `.editorconfig` section glob. The
/// widely used subset is implemented here rather than pulled in:
/// `*`, `**`, `?`, `[abc]`, `[!abc]` and `{a,b}` alternatives cover
/// every real configuration, and no Swift package for the format
/// meets this project's admission rule. Numeric `{1..9}` ranges and
/// backslash escapes are deliberately not supported; a glob using
/// them simply matches nothing rather than matching wrongly.
public extension EditorConfig {
    /// Whether a section's glob covers a path relative to the
    /// directory holding its `.editorconfig`. A glob without a
    /// slash matches the file's name in any directory; one starting
    /// with a slash is anchored at that directory.
    static func matches(glob: String, path: String) -> Bool {
        for expanded in expanded(glob) {
            let anchored = expanded.contains("/")
            let pattern = anchored && expanded.hasPrefix("/") ? String(expanded.dropFirst()) : expanded
            let target = anchored ? path : String(path.split(separator: "/").last ?? "")
            if matches(Array(pattern)[...], Array(target)[...]) {
                return true
            }
        }
        return false
    }

    // MARK: Private

    /// One glob per `{a,b}` alternative, recursively, so several
    /// groups multiply out; a group without a closing brace is
    /// literal text.
    private static func expanded(_ glob: String) -> [String] {
        guard let open = glob.firstIndex(of: "{"),
              let close = glob[open...].firstIndex(of: "}")
        else {
            return [glob]
        }

        let prefix = glob[..<open]
        let suffix = glob[glob.index(after: close)...]
        let body = glob[glob.index(after: open) ..< close]
        return body
            .split(separator: ",", omittingEmptySubsequences: false)
            .flatMap { expanded(String(prefix) + String($0) + String(suffix)) }
    }

    private static func matches(_ pattern: ArraySlice<Character>, _ path: ArraySlice<Character>) -> Bool {
        guard let token = pattern.first else {
            return path.isEmpty
        }

        switch token {
        case "*":
            return matchesWildcard(pattern, path)

        case "?":
            guard let head = path.first, head != "/" else {
                return false
            }

            return matches(pattern.dropFirst(), path.dropFirst())

        case "[":
            return matchesClass(pattern, path)

        default:
            guard path.first == token else {
                return false
            }

            return matches(pattern.dropFirst(), path.dropFirst())
        }
    }

    /// `**` swallows anything, separators included; a single `*`
    /// stops at one.
    private static func matchesWildcard(_ pattern: ArraySlice<Character>, _ path: ArraySlice<Character>) -> Bool {
        let rest = pattern.dropFirst()
        let crossesDirectories = rest.first == "*"
        let remainder = crossesDirectories ? rest.dropFirst() : rest
        var tail = path
        while true {
            if matches(remainder, tail) {
                return true
            }
            guard let head = tail.first, crossesDirectories || head != "/" else {
                return false
            }

            tail = tail.dropFirst()
        }
    }

    /// `[abc]`, `[a-z]` and their negations, one character each and
    /// never a separator; an unclosed or empty bracket is literal
    /// text.
    private static func matchesClass(_ pattern: ArraySlice<Character>, _ path: ArraySlice<Character>) -> Bool {
        let body = pattern.dropFirst()
        guard let close = body.firstIndex(of: "]"), close > body.startIndex,
              let head = path.first, head != "/"
        else {
            guard path.first == "[" else {
                return false
            }

            return matches(body, path.dropFirst())
        }

        var members = body[..<close]
        let isNegated = members.first == "!" || members.first == "^"
        if isNegated {
            members = members.dropFirst()
        }
        return contains(members, head) != isNegated
            && matches(body[body.index(after: close)...], path.dropFirst())
    }

    /// Whether a class's members cover a character, ranges included.
    private static func contains(_ members: ArraySlice<Character>, _ character: Character) -> Bool {
        var rest = members
        while let lower = rest.first {
            let afterLower = rest.dropFirst()
            // `a-z`, when a dash has something on both sides of it.
            if afterLower.first == "-", let upper = afterLower.dropFirst().first {
                if lower <= character, character <= upper {
                    return true
                }

                rest = afterLower.dropFirst().dropFirst()
                continue
            }
            if lower == character {
                return true
            }

            rest = afterLower
        }
        return false
    }
}
