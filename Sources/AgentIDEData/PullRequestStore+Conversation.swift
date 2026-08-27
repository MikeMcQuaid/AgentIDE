import AgentIDEDomain
import Foundation

// MARK: - PullRequestConversation

/// One pull request's conversation as the pane shows it: its
/// description, what has been said since, and the review threads.
public struct PullRequestConversation: Sendable {
    /// The pull request's description.
    public let body: String

    /// The reviews and comments, in the order they arrived.
    public let events: [ReviewComment]

    /// The review threads, from GraphQL when it answered.
    public let threads: [ReviewThread]

    /// Why GraphQL failed, nil when it answered; without it the
    /// missing resolve buttons look like a display bug.
    public let graphQLFailure: String?
}

/// The conversation half of the shared store: the same timer covers
/// a pull request's description, its comments and its threads, since
/// they are one screen and one question as far as anyone reading is
/// concerned.
public extension PullRequestStore {
    /// The conversation, fetched only when the last one is a minute
    /// old. `seededBody` is the description the listing already
    /// carries, which saves fetching it again.
    func conversation(
        repositoryPath: String,
        number: Int,
        seededBody: String?,
        interval: TimeInterval = minimumInterval,
    ) async throws -> PullRequestConversation {
        let key = Self.conversationKey(repositoryPath: repositoryPath, number: number)
        let threadsKey = AppMetadata.threadsKey(repositoryPath: repositoryPath, number: number)
        guard due(key, interval: interval) else {
            return cachedConversation(key: key, threadsKey: threadsKey, seededBody: seededBody)
        }

        let body: String
        let events: [ReviewComment]
        if let seededBody {
            body = seededBody
            events = try await github.reviewComments(repositoryPath: repositoryPath, number: number)
        } else {
            (body, events) = try await github.conversation(repositoryPath: repositoryPath, number: number)
        }
        let answer = await github.conversationThreads(repositoryPath: repositoryPath, number: number)
        store.update { metadata in
            metadata.conversationCache[key] = CachedConversation(body: body, events: events)
            // A REST fallback never overwrites cached GraphQL threads:
            // that would strip the resolve buttons from a reopen.
            if answer.graphQLFailure == nil {
                metadata.threadsCache[threadsKey] = CachedThreads(threads: answer.threads)
            }
            metadata.fetchedAt[key] = Date()
        }
        return PullRequestConversation(
            body: body,
            events: events,
            threads: answer.threads,
            graphQLFailure: answer.graphQLFailure,
        )
    }

    /// What the app already knows, for painting before anything is
    /// asked and for answering a question asked too soon.
    func cachedConversation(repositoryPath: String, number: Int, seededBody: String? = nil) -> PullRequestConversation {
        cachedConversation(
            key: Self.conversationKey(repositoryPath: repositoryPath, number: number),
            threadsKey: AppMetadata.threadsKey(repositoryPath: repositoryPath, number: number),
            seededBody: seededBody,
        )
    }

    private func cachedConversation(key: String, threadsKey: String, seededBody: String?) -> PullRequestConversation {
        let metadata = store.load()
        let cached = metadata.conversationCache[key]
        return PullRequestConversation(
            body: seededBody ?? cached?.body ?? "",
            events: cached?.events ?? [],
            threads: metadata.threadsCache[threadsKey]?.threads ?? [],
            graphQLFailure: nil,
        )
    }
}
