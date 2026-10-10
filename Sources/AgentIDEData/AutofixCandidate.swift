import AgentIDEDomain

struct AutofixCandidate: Equatable {
    let counts: [AutofixAttempt.Kind: Int]
    let sources: Set<AutofixAttempt.Kind>
    let events: Set<String>
    let text: String
    var localThreadIDs: Set<String> = []
    let threads: [String: PendingThreadResolution]

    static func combine(_ candidates: [Self]) -> Self? {
        guard candidates.isEmpty == false else {
            return nil
        }

        return Self(
            counts: candidates.reduce(into: [:]) { $0.merge($1.counts, uniquingKeysWith: +) },
            sources: Set(candidates.flatMap(\.sources)),
            events: Set(candidates.flatMap(\.events)),
            text: candidates.map(\.text).joined(separator: "\n\n"),
            localThreadIDs: Set(candidates.flatMap(\.localThreadIDs)),
            threads: candidates.reduce(into: [:]) { $0.merge($1.threads) { first, _ in first } },
        )
    }

    static func checks(summary: PullRequestSummary, state: PullRequestAutomation) -> Self? {
        guard state.autofixCI else {
            return nil
        }

        let failures = (summary.autofixChecks?.failures ?? []).filter { check in
            check.runID.isEmpty == false && state.handledEvents.contains(check.runID) == false
        }
        guard failures.isEmpty == false else {
            return nil
        }

        return Self(
            counts: [.checks: failures.count],
            sources: [.checks],
            events: Set(failures.map(\.runID)),
            text: "Fix these failed required CI jobs on this head:\n"
                + failures.lazy.map { $0.name + ": " + $0.conclusion + "\n" + $0.link }.joined(separator: "\n\n"),
            threads: [:],
        )
    }

    static func localReview(_ review: LocalReview, head: String, state: PullRequestAutomation) -> Self? {
        let event = "local:" + (review.runID ?? review.revision + ":" + review.snapshot)
        guard state.autofixLocalReviews, state.handledEvents.contains(event) == false,
              let prompt = review.prompt()
        else {
            return nil
        }

        return Self(
            counts: [.localReview: review.remaining],
            sources: [.localReview],
            events: [event],
            text: prompt + "\n\nFinding identifiers:\n"
                + review.threads
                .filter { $0.isResolved == false }
                .lazy
                .map { $0.id + ": " + $0.asText }
                .joined(separator: "\n\n"),
            localThreadIDs: Set(review.threads.filter { $0.isResolved == false }.map(\.id)),
            threads: Dictionary(uniqueKeysWithValues: review.threads.filter { $0.isResolved == false }.map { thread in
                (thread.id, PendingThreadResolution(head: head, commentID: review.runID ?? review.revision))
            }),
        )
    }

    static func reviews(
        threads: [ReviewThread],
        head: String,
        writers: Set<String>,
        state: PullRequestAutomation,
    ) -> Self? {
        guard state.autofixReviews || state.autofixBots else {
            return nil
        }

        var reviewCounts = [AutofixAttempt.Kind: Int]()
        var commentEvents = Set<String>()
        var marks = [String: PendingThreadResolution]()
        var sections = [String]()
        for thread in threads where thread.isResolved == false && thread.resolveID.isEmpty == false {
            guard let latest = thread.comments.last?.id else {
                continue
            }

            let comments = thread.comments.filter { comment in
                let human = state.autofixReviews && comment.authorType == "User" && writers.contains(comment.author)
                let bot = state.autofixBots && botSource(author: comment.author, type: comment.authorType) != nil
                return (human || bot)
                    && comment.id.map { state.handledEvents.contains("comment:" + $0) == false } == true
            }
            guard comments.isEmpty == false else {
                continue
            }

            for comment in comments {
                let kind = botSource(author: comment.author, type: comment.authorType) ?? .reviews
                reviewCounts[kind, default: 0] += 1
            }
            commentEvents.formUnion(comments.compactMap { $0.id.map { "comment:" + $0 } })
            marks[thread.resolveID] = PendingThreadResolution(head: head, commentID: latest)
            sections.append("Thread " + thread.resolveID + " in " + thread.path
                + (thread.line.map { ":" + String($0) } ?? "") + "\n"
                + comments.lazy.map { $0.author + ": " + $0.body }.joined(separator: "\n"))
        }
        guard commentEvents.isEmpty == false else {
            return nil
        }

        return Self(
            counts: reviewCounts,
            sources: Set(reviewCounts.keys),
            events: commentEvents,
            text: sections.joined(separator: "\n\n"),
            threads: marks,
        )
    }
}
