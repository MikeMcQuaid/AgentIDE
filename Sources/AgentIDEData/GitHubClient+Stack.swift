/// What `gh stack` is for here: linking pull requests into a stack
/// on GitHub. Not asking whether they are a stack: `gh stack view`
/// knows only the stacks it created and tracked locally, and answers
/// "not part of a stack" for a linked one GitHub itself shows as a
/// stack. Split from the client body for length.
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
}
