import Foundation

/// Links within the review's commit listing.
public enum ReviewCommitLink {
    /// The internal URL scheme for commit listings.
    public static let scheme = "agentide-commit"

    /// Accepts only hexadecimal object names, never git options or expressions.
    public static func hash(in url: URL) -> String? {
        guard url.scheme == scheme else {
            return nil
        }

        let hash = String(url.absoluteString.dropFirst(scheme.count + 1))
        return hash.range(of: #"\A[a-fA-F0-9]{4,40}\z"#, options: .regularExpression) != nil ? hash : nil
    }
}
