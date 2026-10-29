import AgentIDEDomain
import Foundation

// MARK: - GitHubAuthentication

/// One recovery and cooldown for every copy of the app's GitHub client.
actor GitHubAuthentication {
    // MARK: Lifecycle

    init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    // MARK: Internal

    static func rejected(_ result: ProcessResult) -> Bool {
        guard result.succeeded == false else {
            return false
        }

        let error = result.standardError
        return error.range(of: #"\bHTTP(?:/\S+)?\s+401\b"#, options: .regularExpression) != nil
            || result.standardOutput.range(of: #"^HTTP/\S+\s+401\b"#, options: .regularExpression) != nil
            || error.contains("refresh_expired")
            || error.contains("To get started with GitHub CLI, please run:  gh auth login")
    }

    func permit(using runner: any ProcessRunner) async throws -> Int {
        guard let failure else {
            return generation
        }

        let task: Task<Void, Never>
        if let checking {
            task = checking
        } else {
            guard now() >= retryAt else {
                throw failure
            }

            generation += 1
            task = Task {
                // Stale overrides must stop shadowing gh's stored login throughout the app.
                unsafe unsetenv("GH_TOKEN")
                unsafe unsetenv("GITHUB_TOKEN")
                let result = try? await runner.run(
                    ["gh", "auth", "status", "--active", "--hostname", "github.com"],
                    workingDirectory: nil,
                    environment: ["GH_PROMPT_DISABLED": "1"],
                )
                checking = nil
                retryAt = now().addingTimeInterval(RefreshCadence.githubAuthenticationSeconds)
                if result?.succeeded == true {
                    self.failure = nil
                }
            }
            checking = task
        }
        await task.value
        if let failure = self.failure {
            throw failure
        }

        return generation
    }

    func recover(after attempt: Int, using runner: any ProcessRunner) async throws -> Int {
        if attempt == generation, failure == nil {
            failure = lastFailure ?? GitHubAuthenticationError()
            lastFailure = failure
            retryAt = .distantPast
        }
        return try await permit(using: runner)
    }

    func reject(after attempt: Int) -> GitHubAuthenticationError {
        if attempt == generation {
            failure = lastFailure ?? GitHubAuthenticationError()
            lastFailure = failure
            retryAt = now().addingTimeInterval(RefreshCadence.githubAuthenticationSeconds)
            generation += 1
        }
        return failure ?? GitHubAuthenticationError()
    }

    func succeeded(after attempt: Int) {
        if attempt == generation, failure == nil {
            lastFailure = nil
        }
    }

    // MARK: Private

    private let now: @Sendable () -> Date
    private var generation = 0
    private var failure: GitHubAuthenticationError?
    private var lastFailure: GitHubAuthenticationError?
    private var retryAt: Date = .distantPast
    private var checking: Task<Void, Never>?
}

// MARK: - GitHubAuthenticationError

/// A shared sign-in failure, reported once even when many panes encounter it.
public struct GitHubAuthenticationError: LocalizedError {
    // MARK: Lifecycle

    init(recovered: Bool = false) {
        self.recovered = recovered
    }

    // MARK: Public

    public let id: UUID = .init()

    public var errorDescription: String? {
        if recovered {
            return "GitHub sign-in recovered. Retry the action; it was not repeated automatically."
        }
        return "GitHub sign-in failed and automatic credential recovery failed too. Background requests are paused. "
            + "AgentIDE will check again within a minute."
    }

    // MARK: Private

    private let recovered: Bool
}
