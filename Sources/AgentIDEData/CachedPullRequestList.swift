import AgentIDEDomain
import Foundation

// MARK: - CachedConversation

/// One pull request's cached body and feedback timeline.
public struct CachedConversation: Codable, Equatable, Sendable {
    // MARK: Lifecycle

    /// Creates a cached conversation stamped now by default.
    public init(body: String = "", events: [ReviewComment] = [], savedAt: Date = Date()) {
        self.body = body
        self.events = events
        self.savedAt = savedAt
    }

    /// Decodes tolerantly: entries cached before the stamp existed
    /// count as oldest rather than failing the whole metadata load.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
        events = try container.decodeIfPresent([ReviewComment].self, forKey: .events) ?? []
        savedAt = try container.decodeIfPresent(Date.self, forKey: .savedAt) ?? .distantPast
    }

    // MARK: Public

    /// The pull request's description.
    public var body: String

    /// The reviews and comments, in fetched order.
    public var events: [ReviewComment]

    /// When the conversation was cached, for eviction.
    public var savedAt: Date
}

// MARK: - CachedSummary

/// One enriched pull request header, stamped so the cap can evict
/// the oldest.
public struct CachedSummary: Codable, Equatable, Sendable {
    // MARK: Lifecycle

    /// Creates a cached header stamped now by default.
    public init(summary: PullRequestSummary, savedAt: Date = Date()) {
        self.summary = summary
        self.savedAt = savedAt
    }

    // MARK: Public

    /// The enriched summary.
    public let summary: PullRequestSummary

    /// When the header was cached.
    public let savedAt: Date
}

// MARK: - CachedThreads

/// One conversation's review threads, stamped so the cap can evict
/// the oldest.
public struct CachedThreads: Codable, Equatable, Sendable {
    // MARK: Lifecycle

    /// Creates cached threads stamped now by default.
    public init(threads: [ReviewThread], savedAt: Date = Date()) {
        self.threads = threads
        self.savedAt = savedAt
    }

    // MARK: Public

    /// The conversation threads.
    public let threads: [ReviewThread]

    /// When the threads were cached.
    public let savedAt: Date
}

// MARK: - CachedPullRequestList

/// One repository scope's cached pull request listing, stamped so
/// the cap can evict the oldest.
public struct CachedPullRequestList: Codable, Equatable, Sendable {
    // MARK: Lifecycle

    /// Creates a cached listing stamped now by default.
    public init(summaries: [PullRequestSummary], savedAt: Date = Date()) {
        self.summaries = summaries
        self.savedAt = savedAt
    }

    // MARK: Public

    /// The listing as fetched.
    public var summaries: [PullRequestSummary]

    /// When the listing was cached, for eviction.
    public var savedAt: Date
}
