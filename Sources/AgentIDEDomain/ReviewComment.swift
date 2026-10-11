import Foundation

// MARK: - ReviewComment

/// One comment on a pull request, from a review or the
/// thread. Codable so conversations can cache between runs.
public struct ReviewComment: Identifiable, Hashable, Sendable, Codable {
    // MARK: Lifecycle

    /// Creates a comment.
    public init(
        id: Int,
        author: String,
        body: String,
        kind: String = "",
        nodeID: String? = nil,
        authorType: String? = nil,
        commit: String? = nil,
        date: Date? = nil,
    ) {
        self.id = id
        self.author = author
        self.body = body
        self.kind = kind
        self.nodeID = nodeID
        self.authorType = authorType
        self.commit = commit
        self.date = date
    }

    // MARK: Public

    /// The timeline identity; REST reviews and issue comments use separate signs.
    public let id: Int

    /// The GitHub login of the author.
    public let author: String

    /// The comment text.
    public let body: String

    /// The review state that produced this entry, such as
    /// `APPROVED`; empty for plain comments.
    public let kind: String
    public let nodeID: String?
    public let authorType: String?
    public let commit: String?
    public let date: Date?
}
