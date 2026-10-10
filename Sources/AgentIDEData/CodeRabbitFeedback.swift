import AgentIDEDomain
import Foundation

// MARK: - BotReviewCompletion

struct BotReviewCompletion {
    let id: String
    let date: Date
}

// MARK: - CodeRabbitFeedback

/// Only CodeRabbit's finding sections and explicit completion evidence count.
enum CodeRabbitFeedback {
    static func completion(_ events: [ReviewComment], head: String) -> BotReviewCompletion? {
        completions(events, head: head).max { $0.date < $1.date }
    }

    static func completions(_ events: [ReviewComment], head: String) -> [BotReviewCompletion] {
        events.compactMap { event -> BotReviewCompletion? in
            guard event.authorType == "Bot", ReviewBot.codeRabbit.matches(event.author),
                  let id = event.nodeID, let date = event.date
            else {
                return nil
            }

            if event.commit == head, ["COMMENTED", "APPROVED", "CHANGES_REQUESTED"].contains(event.kind) {
                return BotReviewCompletion(id: id, date: date)
            }
            guard event.kind.isEmpty,
                  let start = event.body.range(of: "<!-- recent_review_start -->")?.upperBound,
                  let end = event.body
                  .range(of: "<!-- recent_review_end -->", range: start ..< event.body.endIndex)?
                  .lowerBound
            else {
                return nil
            }

            let recent = String(event.body[start ..< end])
            guard recent.contains("No actionable comments were generated in the recent review."),
                  recent.contains(" and " + head + "."),
                  let run = recent.components(separatedBy: "**Run ID**: `")
                  .dropFirst()
                  .first?
                  .split(separator: "`")
                  .first, run.isEmpty == false
            else {
                return nil
            }

            return BotReviewCompletion(id: id + ":" + run, date: date)
        }
    }

    static func findings(_ review: ReviewComment, head: String) -> String? {
        guard review.authorType == "Bot", ReviewBot.codeRabbit.matches(review.author),
              review.commit == head, ["COMMENTED", "CHANGES_REQUESTED", "APPROVED"].contains(review.kind),
              let section = review.body.range(
                  of: #"<summary>[^<]*(Nitpick comments|Outside diff range comments) \([1-9][0-9]*\)</summary>"#,
                  options: .regularExpression,
              )
        else {
            return nil
        }

        let end = review.body
            .range(
                of: #"<details>\s*<summary>ℹ️ Review info</summary>"#,
                options: .regularExpression,
                range: section.upperBound ..< review.body.endIndex,
            )?.lowerBound ?? review.body.endIndex
        return String(review.body[section.lowerBound ..< end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
