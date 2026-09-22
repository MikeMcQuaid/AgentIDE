import AgentIDEDomain
import Foundation

extension LocalReviewInput {
    /// Retains the exchange even when the CLI fails or returns an invalid result.
    static func review(
        result: ProcessResult,
        files: [DiffFile],
        adapter: any AgentRunner,
        revision: String,
        input: String,
    ) -> LocalReview {
        var findings = [ReviewThread]()
        var failure: String?
        do {
            guard result.outputLimitExceeded == false else {
                throw SessionServiceError("The reviewer exceeded the 256 KiB output limit and was stopped.")
            }
            guard result.succeeded else {
                throw SessionServiceError("The reviewer exited with status " + String(result.status) + ". Try again.")
            }

            findings = try threads(
                from: adapter.reviewOutput(result.standardOutput), files: files, reviewer: adapter.kind,
            )
        } catch {
            failure = bounded(error.localizedDescription)
        }
        var review = LocalReview(
            reviewer: adapter.kind,
            snapshot: fingerprint(snapshot(files: files)),
            revision: revision,
            threads: findings,
        )
        review.input = input
        review.output = bounded(result.standardOutput)
        review.diagnostics = bounded(result.standardError)
        review.failure = failure
        return review
    }

    private static func bounded(_ text: String) -> String {
        guard text.utf8.count > byteLimit else {
            return text
        }

        // The byte limit can split UTF-8; keep the prefix with replacement characters.
        // swiftlint:disable:next optional_data_string_conversion
        return String(decoding: text.utf8.prefix(byteLimit), as: UTF8.self) + "\n[Output truncated]"
    }
}
