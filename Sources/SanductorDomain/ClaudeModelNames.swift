/// How a Claude alias is written for a person, worked out from the
/// model identifiers Claude Code itself has recorded rather than from
/// a list written here.
///
/// `claude --model` takes an alias (`fable`, `opus`), which says
/// nothing about which version it stands for, and Claude Code has no
/// listing subcommand to ask. What it does have is its own record of
/// the identifiers it has used, and those carry the version:
/// `claude-fable-5-1` is Fable 5.1. A version nobody has used does not
/// appear, which is the honest answer: the alias alone is then shown.
public enum ClaudeModelNames {
    // MARK: Public

    /// Alias to display name, keeping the newest version seen of each
    /// family. Identifiers it cannot read contribute nothing.
    public static func names(fromIdentifiers identifiers: [String]) -> [String: String] {
        var best = [String: [Int]]()
        for identifier in identifiers {
            guard let (family, version) = parse(identifier) else {
                continue
            }

            if let seen = best[family], isNewer(seen, than: version) {
                continue
            }

            best[family] = version
        }
        return best.mapValues { version in
            version.map(String.init).joined(separator: ".")
        }
        .reduce(into: [String: String]()) { names, entry in
            names[entry.key] = entry.key.capitalized + " " + entry.value
        }
    }

    // MARK: Private

    /// `20251001`: a date rather than a version part.
    private static let releaseDateLength = 8

    /// `claude`, then the family, then the version: the identifier
    /// has to carry all three to say anything.
    private static let shortestIdentifier = 3

    /// The family and version an identifier carries:
    /// `claude-fable-5-1[1m]` is fable 5.1, and the release date some
    /// identifiers end with is not part of the version.
    private static func parse(_ identifier: String) -> (family: String, version: [Int])? {
        let bare = identifier.prefix { $0 != "[" }
        let parts = bare.split(separator: "-").map(String.init)
        guard parts.first == "claude", parts.count >= shortestIdentifier else {
            return nil
        }

        let named = parts.dropFirst()
        guard let family = named.first, family.allSatisfy(\.isLetter) else {
            return nil
        }

        let version = named.dropFirst()
            .prefix { $0.count < releaseDateLength }
            .compactMap { Int($0) }
        return version.isEmpty ? nil : (family, version)
    }

    /// Whether one version is above another, compared part by part so
    /// 5.1 beats 5 and 10 beats 9.
    private static func isNewer(_ version: [Int], than other: [Int]) -> Bool {
        for (mine, theirs) in zip(version, other) where mine != theirs {
            return mine > theirs
        }
        return version.count > other.count
    }
}
