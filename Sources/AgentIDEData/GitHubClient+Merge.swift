import Foundation

public extension GitHubClient {
    /// Acceptance or queue admission does not mean the pull request merged.
    enum MergeResult: String, Sendable {
        // SwiftFormat removes raw values identical to case names.
        // swiftlint:disable explicit_enum_raw_value
        case pending
        case merged
        case enqueued
        // swiftlint:enable explicit_enum_raw_value
    }

    /// Merges or queues a pull request and its linked downstack pull
    /// requests, returning as soon as GitHub accepts the request.
    @discardableResult
    func merge(repositoryPath: String, number: Int) async throws -> MergeResult {
        let path = "repos/{owner}/{repo}/pulls/\(number)/merge-async"
        let method = await mergeMethodFlag(repositoryPath: repositoryPath).replacing("--", with: "")
        let arguments = [
            "api", "--method", "PUT", path,
            "--include", "--header", "Accept: application/vnd.github+json",
            "--header", "X-GitHub-Api-Version: 2026-03-10",
            "--raw-field", "merge_method=" + method, "--raw-field", "merge_action=default",
        ]
        let result = try await gh(arguments, in: repositoryPath, allowFailure: true)
        let (headers, body) = Self.splitHeaders(result.standardOutput)
        let existing = headers.first?.contains(" 409 ") == true
        guard result.succeeded || existing else {
            throw CommandError(command: "gh api " + path, result: result)
        }

        let response = try JSONDecoder().decode(AsyncMergeResponse.self, from: Data(body.utf8))
        guard existing == false || response.status == "pending" else {
            throw CommandError(command: "gh api " + path, result: result)
        }
        guard let outcome = MergeResult(rawValue: response.status) else {
            throw AsyncMergeError(message: response.details.message ?? "GitHub returned an invalid merge result.")
        }

        return outcome
    }
}

// MARK: - AsyncMergeResponse

private struct AsyncMergeResponse: Decodable {
    struct Details: Decodable {
        let message: String?
    }

    let status: String
    let details: Details
}

// MARK: - AsyncMergeError

private struct AsyncMergeError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}
