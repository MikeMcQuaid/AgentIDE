import Foundation

/// Commit navigation uses the same worktree-scoped bus as editor requests.
public enum ReviewCommitLink {
    // MARK: Public

    /// The internal URL scheme shared by comments and commit listings.
    public static let scheme = "agentide-commit"
    /// A counter so clicking the same commit again opens it again.
    public static let requestKey = "reviewCommitRequest"

    /// Accepts only hexadecimal object names, never git options or expressions.
    public static func hash(in url: URL) -> String? {
        guard url.scheme == scheme else {
            return nil
        }

        let hash = String(url.absoluteString.dropFirst(scheme.count + 1))
        return isHash(hash) ? hash : nil
    }

    /// Shows Review and requests the commit in the containing worktree.
    public static func open(_ url: URL, worktreePath: String, defaults: UserDefaults = .standard) -> Bool {
        guard let hash = hash(in: url) else {
            return false
        }

        defaults.set(hash, forKey: hashKey)
        defaults.set(worktreePath, forKey: worktreeKey)
        defaults.set(defaults.integer(forKey: requestKey) + 1, forKey: requestKey)
        defaults.set("review", forKey: UtilityTabTarget.key)
        defaults.set(true, forKey: UtilityTabTarget.visibilityKey)
        return true
    }

    /// Other mounted worktrees ignore the request.
    public static func requestedCommit(worktreePath: String, defaults: UserDefaults = .standard) -> String? {
        guard defaults.string(forKey: worktreeKey) == worktreePath else {
            return nil
        }

        return defaults.string(forKey: hashKey)
    }

    // MARK: Internal

    static func isHash(_ text: String) -> Bool {
        text.range(of: #"\A[a-fA-F0-9]{4,40}\z"#, options: .regularExpression) != nil
    }

    // MARK: Private

    private static let hashKey = "reviewCommitHash"
    private static let worktreeKey = "reviewCommitWorktree"
}
