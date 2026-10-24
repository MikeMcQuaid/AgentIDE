import AgentIDEDomain
import AppKit
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

    /// Try the established merge or queue operation before the async API.
    @discardableResult
    func merge(repositoryPath: String, number: Int, usingMergeQueue: Bool = false) async throws -> MergeResult {
        try Task.checkCancellation()
        let path = "repos/{owner}/{repo}/pulls/\(number)/merge"
        let method = await usingMergeQueue ? [] : [
            "--raw-field", "merge_method=" + mergeMethodFlag(repositoryPath: repositoryPath).replacing("--", with: ""),
        ]
        let arguments = [
            "api", "--include", "--header", "Accept: application/vnd.github+json",
            "--header", "X-GitHub-Api-Version: 2026-03-10",
        ]
        let synchronousFailure: String
        do {
            if usingMergeQueue {
                try await gh(["pr", "merge", String(number)], in: repositoryPath)
                return try await confirmedQueueState(number: number, repositoryPath: repositoryPath)
            }

            return try await Self.mergeResult(
                gh(arguments + ["--method", "PUT", path] + method, in: repositoryPath, allowFailure: true),
                path: path,
                asynchronously: false,
            )
            .outcome
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            synchronousFailure = error.localizedDescription
            PerformanceLog.recordMessage("Synchronous merge failed: " + synchronousFailure, isError: false)
        }
        try Task.checkCancellation()
        do {
            return try await confirmedMerge(
                gh(
                    arguments + ["--method", "PUT", path + "-async", "--raw-field", "merge_action=default"] + method,
                    in: repositoryPath,
                    allowFailure: true,
                ),
                path: path + "-async",
                arguments: arguments,
                repositoryPath: repositoryPath,
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            throw MergeError(message: "Synchronous merge failed: " + synchronousFailure
                + "\nAsynchronous merge failed: " + error.localizedDescription)
        }
    }

    private func confirmedQueueState(number: Int, repositoryPath: String) async throws -> MergeResult {
        let query = "query($owner: String!, $name: String!, $number: Int!) "
            + "{ repository(owner: $owner, name: $name) { pullRequest(number: $number) "
            + "{ merged autoMergeRequest { enabledAt } mergeQueueEntry { id } } } }"
        let result = try await gh([
            "api", "graphql", "-f", "query=" + query,
            "-F", "owner={owner}", "-F", "name={repo}", "-F", "number=" + String(number),
            "--jq", ".data.repository.pullRequest",
        ], in: repositoryPath)
        let state = try JSONDecoder().decode(QueueMergeResponse.self, from: Data(result.standardOutput.utf8))
        if state.merged {
            return .merged
        }
        if state.mergeQueueEntry != nil {
            return .enqueued
        }
        if state.autoMergeRequest != nil {
            return .pending
        }
        throw MergeError(message: "GitHub did not confirm queue admission or enabled automerge.")
    }

    private func confirmedMerge(
        _ initial: ProcessResult, path: String, arguments: [String], repositoryPath: String,
    ) async throws -> MergeResult {
        var result = initial
        var resultPath = path
        let deadline = mergePolling.now() + .seconds(RefreshCadence.mergeResultTimeout)
        while true {
            let response = try Self.mergeResult(result, path: resultPath, asynchronously: true)
            guard response.outcome == .pending else {
                return response.outcome
            }
            guard let requestID = response.requestID, UUID(uuidString: requestID) != nil else {
                throw MergeError(message: "GitHub accepted the merge but returned no valid result identifier.")
            }

            try Task.checkCancellation()
            guard mergePolling.now() < deadline else {
                throw MergeError(message: "GitHub has not confirmed the merge or queue admission yet. "
                    + "Check the pull request before retrying.")
            }

            // GitHub sends no completion event to the app for an async request.
            if resultPath != path {
                let interval = await mergePolling.interval()
                try await mergePolling.sleep(min(interval, max(.zero, mergePolling.now().duration(to: deadline))))
            }
            try Task.checkCancellation()
            resultPath = path + "/" + requestID
            do {
                result = try await gh(arguments + ["--method", "GET", resultPath], in: repositoryPath)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
                PerformanceLog.recordMessage("Merge result check failed: " + error.localizedDescription, isError: false)
            }
        }
    }

    private static func mergeResult(
        _ result: ProcessResult,
        path: String,
        asynchronously: Bool,
    ) throws -> (outcome: MergeResult, requestID: String?) {
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

            return (.merged, nil)
        }
        let response = try JSONDecoder().decode(AsyncMergeResponse.self, from: Data(body.utf8))
        guard existing == false || response.status == "pending" else {
            throw CommandError(command: "gh api " + path, result: result)
        }
        guard let outcome = MergeResult(rawValue: response.status) else {
            throw MergeError(message: response.details.message ?? "GitHub returned an invalid merge result.")
        }

        return (outcome, response.details.uuid)
    }
}

// MARK: - MergePolling

struct MergePolling {
    var now: @Sendable () -> ContinuousClock.Instant = { .now }
    var sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    var interval: @Sendable () async -> Duration = {
        let visible = await MainActor.run {
            NSApp?.windows.contains { $0.occlusionState.contains(.visible) } ?? true
        }
        return .seconds(RefreshCadence.pollSeconds(
            setting: RefreshCadence.mergeResultSeconds, visible: visible, onBattery: PowerSource.isOnBattery,
        ))
    }
}

// MARK: - SyncMergeResponse

private struct SyncMergeResponse: Decodable {
    let merged: Bool
    let message: String?
}

// MARK: - QueueMergeResponse

private struct QueueMergeResponse: Decodable {
    struct Entry: Decodable {
        // Presence confirms queue admission.
    }

    let merged: Bool
    let autoMergeRequest: GitHubClient.AutoMergeRow?
    let mergeQueueEntry: Entry?
}

// MARK: - AsyncMergeResponse

private struct AsyncMergeResponse: Decodable {
    struct Details: Decodable {
        let message: String?
        let uuid: String?
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
