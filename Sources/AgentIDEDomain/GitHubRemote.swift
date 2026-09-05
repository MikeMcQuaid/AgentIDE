import Foundation

/// What a git remote URL says about the repository behind it. GitHub
/// hands out two forms, `git@github.com:owner/name.git` and
/// `https://github.com/owner/name`, and both name the owner and the
/// repository in the same place.
public enum GitHubRemote {
    // MARK: Public

    /// The `owner/name` a URL points at, nil when it points anywhere
    /// but GitHub or names no repository.
    public static func fullName(ofURL url: String) -> String? {
        guard let range = url.range(of: host), isHost(range, in: url) else {
            return nil
        }

        let path = url[range.upperBound...].trimmingCharacters(in: separators)
        let parts = path.split(separator: "/").map(String.init)
        guard let owner = parts.first, let repository = parts.dropFirst().first else {
            return nil
        }

        let suffix = ".git"
        let name = repository.hasSuffix(suffix) ? String(repository.dropLast(suffix.count)) : repository
        return name.isEmpty ? nil : owner + "/" + name
    }

    /// The account a URL's repository belongs to.
    public static func owner(ofURL url: String) -> String? {
        fullName(ofURL: url)?.split(separator: "/").first.map(String.init)
    }

    /// Whether a configured remote is a URL rather than a remote's
    /// name, which is what `gh pr checkout` leaves behind for a pull
    /// request opened from a fork.
    public static func isURL(_ remote: String) -> Bool {
        remote.contains("://") || remote.contains("@") || remote.contains("/")
    }

    // MARK: Private

    private static let host = "github.com"

    private static let separators: CharacterSet = .init(charactersIn: ":/")

    /// Whether a match is the URL's host rather than part of a
    /// longer name: `evilgithub.com` and `github.com.example.org`
    /// are somebody else's, however much they look like this one.
    private static func isHost(_ match: Range<String.Index>, in url: String) -> Bool {
        let before = match.lowerBound == url.startIndex ? nil : url[url.index(before: match.lowerBound)]
        guard before == nil || before == "/" || before == "@" else {
            return false
        }

        let after = match.upperBound == url.endIndex ? nil : url[match.upperBound]
        return after == "/" || after == ":"
    }
}
