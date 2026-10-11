import AgentIDEDomain
import Foundation

// MARK: - PullRequestAutomation

/// Durable per-PR preferences, pending work and side-effect claims.
public struct PullRequestAutomation: Codable, Equatable, Sendable {
    // MARK: Lifecycle

    public init(repositoryPath: String, number: Int, url: String) {
        self.repositoryPath = repositoryPath
        self.number = number
        self.url = url
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        repositoryPath = try container.decode(String.self, forKey: .repositoryPath)
        number = try container.decode(Int.self, forKey: .number)
        url = try container.decode(String.self, forKey: .url)
        localWorktreePath = try container.decodeIfPresent(String.self, forKey: .localWorktreePath)
        feedbackWorktreePath = try container.decodeIfPresent(String.self, forKey: .feedbackWorktreePath)
        isAutomatic = try container.decodeIfPresent(Bool.self, forKey: .isAutomatic) ?? false
        preparingExistingWork = try container.decodeIfPresent(Bool.self, forKey: .preparingExistingWork)
        loopResult = try container.decodeIfPresent(FeedbackLoopResult.self, forKey: .loopResult)
        roundLimit = try container.decodeIfPresent(Int.self, forKey: .roundLimit) ?? 1
        roundsStarted = try container.decodeIfPresent(Int.self, forKey: .roundsStarted) ?? 0
        localRounds = try container.decodeIfPresent(LocalAutofixRounds.self, forKey: .localRounds)
        autofixCopilot = try container.decodeIfPresent(Bool.self, forKey: .autofixCopilot) ?? false
        codeRabbitEnabled = try container.decodeIfPresent(Bool.self, forKey: .codeRabbitEnabled)
        botRequests = try container.decodeIfPresent([ReviewBot: BotReviewRequest].self, forKey: .botRequests)
        preferredReviewBot = try container.decodeIfPresent(ReviewBot.self, forKey: .preferredReviewBot)
        reviewer = try container.decodeIfPresent(AgentKind.self, forKey: .reviewer)
        repeatLocalReview = try container.decodeIfPresent(Bool.self, forKey: .repeatLocalReview) ?? false
        copilotHead = try container.decodeIfPresent(String.self, forKey: .copilotHead)
        copilotRequestedAt = try container.decodeIfPresent(Date.self, forKey: .copilotRequestedAt)
        collection = try container.decodeIfPresent(LocalFeedbackCollection.self, forKey: .collection)
        autofixLocalReviews = try container.decodeIfPresent(Bool.self, forKey: .autofixLocalReviews) ?? false
        autofixCI = try container.decodeIfPresent(Bool.self, forKey: .autofixCI) ?? false
        autofixReviews = try container.decodeIfPresent(Bool.self, forKey: .autofixReviews) ?? false
        pushAutomatically = try container.decodeIfPresent(Bool.self, forKey: .pushAutomatically) ?? false
        pending = try container.decodeIfPresent(String.self, forKey: .pending) ?? ""
        lastResult = try container.decodeIfPresent(String.self, forKey: .lastResult) ?? ""
        handledEvents = try container.decodeIfPresent(Set<String>.self, forKey: .handledEvents) ?? []
        resolutions = try container.decodeIfPresent([String: PendingThreadResolution].self, forKey: .resolutions) ?? [:]
        attempt = try container.decodeIfPresent(AutofixAttempt.self, forKey: .attempt)
        failedPush = try container.decodeIfPresent(FailedAutofixPush.self, forKey: .failedPush)
        pushedCommit = try container.decodeIfPresent(String.self, forKey: .pushedCommit)
        pushedFrom = try container.decodeIfPresent(String.self, forKey: .pushedFrom)
        activityLog = try container.decodeIfPresent([FeedbackActivity].self, forKey: .activityLog)
    }

    // MARK: Public

    public static let roundLimits = 1 ... 3

    public let repositoryPath: String
    public let number: Int
    public let url: String
    public var localWorktreePath: String?
    public var feedbackWorktreePath: String?
    public var isAutomatic = false
    // Absent from loops saved before startup reconciliation.
    public var preparingExistingWork: Bool? // swiftlint:disable:this discouraged_optional_boolean
    public var loopResult: FeedbackLoopResult?
    public var roundLimit = 1
    public var roundsStarted = 0
    public var localRounds: LocalAutofixRounds?
    public var autofixCopilot = false
    // Missing in metadata written before CodeRabbit support.
    // swiftlint:disable:next discouraged_optional_boolean
    public var codeRabbitEnabled: Bool?
    // swiftlint:disable:next discouraged_optional_collection
    public var botRequests: [ReviewBot: BotReviewRequest]?
    public var preferredReviewBot: ReviewBot?
    public var reviewer: AgentKind?
    public var repeatLocalReview = false
    public var copilotHead: String?
    public var copilotRequestedAt: Date?
    public var collection: LocalFeedbackCollection?
    public var autofixLocalReviews = false
    public var autofixCI = false
    public var autofixReviews = false
    public var pushAutomatically = false
    public var pending = ""
    public var lastResult = ""
    public var handledEvents: Set<String> = []
    public var resolutions: [String: PendingThreadResolution] = [:]
    public var attempt: AutofixAttempt?
    public var failedPush: FailedAutofixPush?
    public var pushedCommit: String?
    public var pushedFrom: String?
    // Absent from older metadata.
    // swiftlint:disable:next discouraged_optional_collection
    public var activityLog: [FeedbackActivity]?

    public var needsRefresh: Bool {
        isAutomatic || resolutions.isEmpty == false || attempt != nil || pushedCommit != nil
            || failedPush != nil
    }

    public var hasRemoteSources: Bool {
        autofixCI || autofixReviews || autofixBots
    }

    public static func key(for url: String) -> String {
        if url.hasPrefix("local:") {
            url
        } else {
            url.lowercased()
        }
    }

    // MARK: Internal

    var hasLocalSources: Bool {
        autofixLocalReviews
    }

    var canStartRound: Bool {
        guard isAutomatic else {
            return false
        }

        if isLocalStage {
            return localRoundsStarted
                < min(Self.roundLimits.upperBound, max(Self.roundLimits.lowerBound, localRoundLimit))
        }
        return hasRemoteSources
            && roundsStarted < min(Self.roundLimits.upperBound, max(Self.roundLimits.lowerBound, roundLimit))
    }

    var selectedSources: Set<AutofixAttempt.Kind> {
        Set([
            AutofixAttempt.Kind.checks: autofixCI, .reviews: autofixReviews,
            .localReview: autofixLocalReviews,
            .copilot: autofixBots, .codeRabbit: autofixBots, .githubReview: autofixBots,
        ]
        .filter(\.value)
        .map(\.key))
    }

    func applying(_ defaults: RepositoryFeedbackDefaults?) -> Self {
        var state = self
        state.reviewer = defaults?.reviewer ?? reviewer
        state.preferredReviewBot = defaults?.reviewBot ?? preferredReviewBot
        return state
    }

    func allows(_ sources: Set<AutofixAttempt.Kind>) -> Bool {
        isAutomatic && sources.allSatisfy(allows)
    }

    func allows(_ kind: AutofixAttempt.Kind) -> Bool {
        switch kind {
        case .checks:
            autofixCI

        case .reviews:
            autofixReviews

        case .codeRabbit,
             .copilot,
             .githubReview:
            autofixBots

        case .unavailable:
            false

        case .localReview:
            autofixLocalReviews

        case .existingWork:
            hasLocalSources || hasRemoteSources
        }
    }

    func matches(_ summary: PullRequestSummary) -> Bool {
        localWorktreePath != nil || summary.url == url
    }
}

// MARK: - PendingThreadResolution

/// A mark is invalid as soon as another comment arrives, even before a push.
public struct PendingThreadResolution: Codable, Equatable, Sendable {
    // MARK: Lifecycle

    public init(head: String, commentID: String) {
        self.head = head
        self.commentID = commentID
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        head = try container.decode(String.self, forKey: .head)
        commentID = try container.decode(String.self, forKey: .commentID)
        requested = try container.decodeIfPresent(Bool.self, forKey: .requested) ?? false
    }

    // MARK: Public

    public let head: String
    public let commentID: String
    public var requested = false
}

// MARK: - AutofixAttempt

/// The fixed delivery target and the result file the agent was asked to write.
public struct AutofixAttempt: Codable, Equatable, Sendable {
    // Persisted spelling follows the existing enum conventions.
    // swiftlint:disable explicit_enum_raw_value raw_value_for_camel_cased_codable_enum
    public enum Kind: String, Codable, Sendable {
        case checks = "ci"
        case reviews
        case localReview
        case existingWork
        case copilot
        case codeRabbit
        case githubReview
        case unavailable

        // MARK: Lifecycle

        /// Keep retired attempt claims readable without authorising another side effect.
        public init(from decoder: any Decoder) throws {
            self = try Self(rawValue: decoder.singleValueContainer().decode(String.self)) ?? .unavailable
        }
    }

    // swiftlint:enable explicit_enum_raw_value raw_value_for_camel_cased_codable_enum

    public let id: String
    public let sources: Set<Kind>
    public let head: String
    public let remoteHead: String
    public let localThreadIDs: Set<String>
    public let branch: String
    public let worktreePath: String
    public let sessionName: String
    public let paneID: String
    public let threads: [String: PendingThreadResolution]
    /// A durable claim for one commit-only follow-up within this attempt.
    public var commitRequestedHead: String?
    /// Absent from older attempts; idle alone does not prove the fixing turn ran.
    public var hasObservedTurn: Bool? // swiftlint:disable:this discouraged_optional_boolean
    public var pushClaimed = false
}

// MARK: - AutofixResult

/// Agent-authored evidence is accepted only for the captured attempt and local tip.
struct AutofixResult: Codable {
    let attemptID: String
    let head: String
    let commit: String
    let addressedThreadIDs: Set<String>
}
