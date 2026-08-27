import AgentIDEDomain
import Foundation

/// What `gh stack` is for: linking pull requests into a stack on
/// GitHub, asking whether they are one, and merging one with
/// everything below it. Split from the client body for length.
public extension GitHubClient {
    /// Asks GitHub to show a branch's open pull requests as a
    /// stack. `gh stack link` links pull requests that already
    /// exist and keeps no local tracking of its own, so the app's
    /// own derivation stays the only thing that decides what a
    /// stack is here.
    func linkStack(worktreePath: String, numbers: [Int]) async throws {
        // The extension links the pull requests it is handed, bottom
        // of the stack first, and keeps no local state.
        try await gh(["stack", "link"] + numbers.map(String.init), in: worktreePath)
    }

    /// The pull request numbers `gh stack` sees in the worktree's
    /// stack, empty when it sees no stack at all. What makes a stack
    /// a stack on GitHub is the link, so this is how the app asks
    /// whether that link is there rather than remembering that it
    /// made one.
    func stackedNumbers(worktreePath: String) async -> [Int] {
        let result = try? await gh(["stack", "view", "--json"], in: worktreePath, allowFailure: true)
        guard let result, result.succeeded else {
            return []
        }

        return Self.numbers(inStackJSON: result.standardOutput)
    }

    /// Merges a stack: every pull request from the bottom up to the
    /// one checked out, in order, however the repository merges.
    func mergeStack(worktreePath: String) async throws {
        try await gh(["stack", "merge"], in: worktreePath)
    }
}
