@testable import AgentIDEData
import Testing

/// What is remembered about where each branch pushes.
struct ForkRemotesTests {
    @Test
    func `a branch that pushes to origin is remembered as one`() {
        let remotes = ForkRemotes()
        #expect(remotes.answer(worktreePath: "/w", branch: "main") == .unasked)

        // The common answer is the one most worth not asking twice:
        // it has to survive being written, which is exactly what a
        // dictionary of optionals could not do.
        remotes.remember(.origin, worktreePath: "/w", branch: "main")
        #expect(remotes.answer(worktreePath: "/w", branch: "main") == .origin)

        remotes.remember(
            .fork(owner: "aholland", remote: "aholland"),
            worktreePath: "/w",
            branch: "quarantine-capability",
        )
        #expect(
            remotes.answer(worktreePath: "/w", branch: "quarantine-capability")
                == .fork(owner: "aholland", remote: "aholland"),
        )
        // Each branch of each worktree answers for itself.
        #expect(remotes.answer(worktreePath: "/other", branch: "main") == .unasked)
    }
}
