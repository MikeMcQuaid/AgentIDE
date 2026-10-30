import Foundation
@testable import SanductorData
import SanductorDomain
import Synchronization
import Testing

extension GitHubAuthenticationTests {
    @Test
    func `concurrent rejections share recovery and cooldown ends with a new check`() async throws {
        let clock = Mutex(Date())
        let authentication = GitHubAuthentication { clock.withLock { $0 } }
        let runner = RecoveryRunner()
        let attempt = try await authentication.permit(using: runner)
        let failures = await withTaskGroup(of: UUID?.self) { group in
            for _ in 0 ..< 20 {
                group.addTask {
                    do {
                        _ = try await authentication.recover(after: attempt, using: runner)
                        return nil
                    } catch let error as GitHubAuthenticationError {
                        return error.id
                    } catch {
                        Issue.record(error)
                        return nil
                    }
                }
            }
            var identifiers = [UUID]()
            for await identifier in group {
                if let identifier {
                    identifiers.append(identifier)
                }
            }
            return identifiers
        }
        #expect(failures.count == 20)
        #expect(Set(failures).count == 1)
        #expect(await runner.calls == 1)
        _ = try? await authentication.permit(using: runner)
        #expect(await runner.calls == 1)
        clock.withLock { $0 = $0.addingTimeInterval(RefreshCadence.githubAuthenticationSeconds) }
        await runner.authenticate()
        _ = try await authentication.permit(using: runner)
        #expect(await runner.calls == 2)
    }

    @Test
    func `recovery checks cannot repeat the error message until an API request succeeds`() async throws {
        let clock = Mutex(Date())
        let authentication = GitHubAuthentication { clock.withLock { $0 } }
        let runner = RecoveryRunner()
        await runner.authenticate()
        let attempt = try await authentication.permit(using: runner)
        let recovered = try await authentication.recover(after: attempt, using: runner)
        let first = await authentication.reject(after: recovered)
        clock.withLock { $0 = $0.addingTimeInterval(RefreshCadence.githubAuthenticationSeconds) }
        let retried = try await authentication.permit(using: runner)
        let second = await authentication.reject(after: retried)
        #expect(first.id == second.id)
    }

    @Test
    func `a rejected retry pauses even when the credential check succeeds`() async {
        let runner = RecoveryRunner()
        await runner.authenticate()
        let client = GitHubClient(runner: runner) { true }
        var failures = [UUID]()
        for _ in 0 ..< 3 {
            do {
                _ = try await client.gh(["api", "user"], in: "/repo")
                Issue.record("The request should remain rejected")
            } catch let error as GitHubAuthenticationError {
                failures.append(error.id)
            } catch {
                Issue.record(error)
            }
        }
        #expect(failures.count == 3)
        #expect(Set(failures).count == 1)
        #expect(await runner.calls == 3)
    }

    @Test(arguments: [
        "gh: Bad credentials (HTTP 401)",
        "HTTP/2 401 Unauthorized",
        "oauth: refresh_expired",
        "To get started with GitHub CLI, please run:  gh auth login",
    ])
    func `credential failures are recognised`(_ diagnostic: String) {
        #expect(GitHubAuthentication.rejected(ProcessResult(status: 1, standardOutput: "", standardError: diagnostic)))
    }

    @Test
    func `an HTTP status line is recognised without treating issue content as a rejection`() {
        #expect(GitHubAuthentication.rejected(ProcessResult(
            status: 1, standardOutput: "HTTP/2 401 Unauthorized\r\n", standardError: "",
        )))
        #expect(GitHubAuthentication.rejected(ProcessResult(
            status: 1, standardOutput: "An issue about HTTP 401", standardError: "HTTP 404 Not Found",
        )) == false)
        #expect(GitHubAuthentication.rejected(ProcessResult(
            status: 0, standardOutput: "HTTP/2 401 Unauthorized", standardError: "",
        )) == false)
    }

    @Test(arguments: [
        ["api", "repos/o/r/issues", "-XPOST"],
        ["api", "repos/o/r/issues", "-ftitle=New"],
        ["api", "repos/o/r/issues", "-Ftitle=New"],
        ["api", "repos/o/r/issues", "--method=PATCH"],
        ["api", "repos/o/r/issues", "--input", "-"],
        ["api", "graphql", "-f", "query=query Read { viewer { login } } mutation Write { change }"],
        ["pr", "merge", "7", "--repo", "o/r"],
    ])
    func `only known read-only commands can be retried`(_ arguments: [String]) {
        #expect(GitHubClient.isReadOnly(arguments) == false)
    }
}

// MARK: - RecoveryRunner

private actor RecoveryRunner: ProcessRunner {
    // MARK: Internal

    var calls = 0

    func authenticate() {
        authenticated = true
    }

    func run(
        _ arguments: [String], workingDirectory _: String?, environment _: [String: String], outputLimit _: Int?,
    ) async throws -> ProcessResult {
        calls += 1
        try await Task.sleep(for: .milliseconds(Self.recoveryDelayMilliseconds))
        return ProcessResult(
            status: arguments.starts(with: ["gh", "auth", "status"]) && authenticated ? 0 : 1,
            standardOutput: "",
            standardError: "gh: Bad credentials (HTTP 401)",
        )
    }

    // MARK: Private

    private static let recoveryDelayMilliseconds = 10

    private var authenticated = false
}
