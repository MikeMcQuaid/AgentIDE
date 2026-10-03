import AgentIDEDomain
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

    /// Plain merges try the synchronous API first; stacks and queues
    /// go straight to async, which also recovers a failed sync merge.
    @discardableResult
    func merge(repositoryPath: String, number: Int, asynchronously: Bool = false) async throws -> MergeResult {
        try Task.checkCancellation()
        let path = "repos/{owner}/{repo}/pulls/\(number)/merge"
        let method = await mergeMethodFlag(repositoryPath: repositoryPath).replacing("--", with: "")
        let arguments = [
            "api", "--method", "PUT",
            "--include", "--header", "Accept: application/vnd.github+json",
            "--header", "X-GitHub-Api-Version: 2026-03-10",
            "--raw-field", "merge_method=" + method,
        ]
        var synchronousFailure: String?
        if asynchronously == false {
            do {
                return try await Self.mergeResult(
                    gh(arguments + [path], in: repositoryPath, allowFailure: true),
                    path: path,
                    asynchronously: false,
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
                synchronousFailure = error.localizedDescription
                PerformanceLog.recordMessage("Synchronous merge failed: " + error.localizedDescription, isError: false)
            }
        }
        try Task.checkCancellation()
        do {
            return try await Self.mergeResult(
                gh(
                    arguments + [path + "-async", "--raw-field", "merge_action=default"],
                    in: repositoryPath,
                    allowFailure: true,
                ),
                path: path + "-async",
                asynchronously: true,
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            guard let synchronousFailure else {
                throw error
            }

            throw MergeError(message: "Synchronous merge failed: " + synchronousFailure
                + "\nAsynchronous merge failed: " + error.localizedDescription)
        }
    }

    private static func mergeResult(
        _ result: ProcessResult,
        path: String,
        asynchronously: Bool,
    ) throws -> MergeResult {
        let (headers, body) = Self.splitHeaders(result.standardOutput)
        let existing = asynchronously && headers.first?.contains(" 409 ") == true
        guard result.succeeded || existing else {
            throw CommandError(command: "gh api " + path, result: result)
        }

        if asynchronously == false {
            let response = try JSONDecoder().decode(SyncMergeResponse.self, from: Data(body.utf8))
            guard response.merged else {
                throw MergeError(message: response.message ?? "GitHub did not confirm the merge.")
            }

            return .merged
        }
        let response = try JSONDecoder().decode(AsyncMergeResponse.self, from: Data(body.utf8))
        guard existing == false || response.status == "pending" else {
            throw CommandError(command: "gh api " + path, result: result)
        }
        guard let outcome = MergeResult(rawValue: response.status) else {
            throw MergeError(message: response.details.message ?? "GitHub returned an invalid merge result.")
        }

        return outcome
    }
}

// MARK: - SyncMergeResponse

private struct SyncMergeResponse: Decodable {
    let merged: Bool
    let message: String?
}

// MARK: - AsyncMergeResponse

private struct AsyncMergeResponse: Decodable {
    struct Details: Decodable {
        let message: String?
    }

    let status: String
    let details: Details
}

// MARK: - MergeError

private struct MergeError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}
