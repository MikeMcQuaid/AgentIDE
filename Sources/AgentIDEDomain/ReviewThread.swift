// MARK: - ReviewThreadComment

/// One comment inside a pull request review conversation.
public struct ReviewThreadComment: Codable, Hashable, Sendable {
    // MARK: Lifecycle

    /// Creates a comment.
    public init(author: String, body: String) {
        self.author = author
        self.body = body
    }

    // MARK: Public

    /// The commenting user's login.
    public let author: String

    /// The comment's markdown body.
    public let body: String
}

// MARK: - ReviewThread

/// One review conversation thread on a pull request, anchored to a
/// file and line, resolvable through the API.
public struct ReviewThread: Codable, Hashable, Identifiable, Sendable {
    // MARK: Lifecycle

    /// Creates a thread; `resolveID` defaults to the id for threads
    /// whose display identity is the resolvable GraphQL node.
    public init(
        id: String,
        path: String,
        line: Int?,
        isResolved: Bool,
        comments: [ReviewThreadComment],
        resolveID: String? = nil,
    ) {
        self.id = id
        self.path = path
        self.line = line
        self.isResolved = isResolved
        self.comments = comments
        self.resolveID = resolveID ?? id
    }

    // MARK: Public

    /// The display identity; duplicated ids would make SwiftUI
    /// lists repeat one row and drop the rest.
    public let id: String

    /// The GraphQL node id resolving mutates; empty for REST
    /// fallback threads, which cannot be resolved.
    public let resolveID: String

    /// The file the thread anchors to.
    public let path: String

    /// The line the thread anchors to, nil for outdated anchors.
    public let line: Int?

    /// Whether the conversation is marked resolved.
    public let isResolved: Bool

    /// The thread's comments in order.
    public let comments: [ReviewThreadComment]

    /// The thread as pasteable text: anchor, then each comment.
    public var asText: String {
        let anchor = path + (line.map { ":" + String($0) } ?? "")
        let body = comments.lazy.map { $0.author + ": " + $0.body }.joined(separator: "\n")
        return anchor + "\n" + body
    }

    /// Several threads as one pasteable text, the file named once
    /// above its threads and each thread opened by its line: what a
    /// prompt needs without the path repeated per thread.
    public static func digest(of threads: [Self]) -> String {
        var order = [String]()
        var byPath = [String: [Self]]()
        for thread in threads {
            if byPath[thread.path] == nil {
                order.append(thread.path)
            }
            byPath[thread.path, default: []].append(thread)
        }
        return order.lazy
            .map { path in
                let body = (byPath[path] ?? []).map { thread in
                    let anchor = thread.line.map { ":" + String($0) + " " } ?? ""
                    return anchor + thread.comments.lazy.map { $0.author + ": " + $0.body }.joined(separator: "\n")
                }
                return path + "\n" + body.joined(separator: "\n")
            }
            .joined(separator: "\n\n")
    }
}
