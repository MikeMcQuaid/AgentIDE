import Foundation
@testable import TerminalUI
import Testing

struct ReviewCommitLinkTests {
    @Test
    func `commit requests target one worktree and repeat`() throws {
        let suite = "review-commit-test-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let url = try #require(URL(string: "agentide-commit:d904c"))
        #expect(ReviewCommitLink.open(url, worktreePath: "/repo/worktree", defaults: defaults))
        #expect(ReviewCommitLink.requestedCommit(worktreePath: "/repo/worktree", defaults: defaults) == "d904c")
        #expect(ReviewCommitLink.requestedCommit(worktreePath: "/repo/other", defaults: defaults) == nil)
        #expect(defaults.string(forKey: UtilityTabTarget.key) == "review")
        #expect(defaults.bool(forKey: UtilityTabTarget.visibilityKey))
        #expect(defaults.integer(forKey: ReviewCommitLink.requestKey) == 1)
        #expect(ReviewCommitLink.open(url, worktreePath: "/repo/worktree", defaults: defaults))
        #expect(defaults.integer(forKey: ReviewCommitLink.requestKey) == 2)
    }

    @Test(arguments: [
        "https://example.com/d904c", "agentide-commit:--help", "agentide-commit:HEAD",
        "agentide-commit:d90", "agentide-commit:d904c/path", "agentide-commit:d904c?other",
        "agentide-commit:d904c%20HEAD", "agentide-commit://d904c",
    ])
    func `only literal commit hashes can be requested`(_ address: String) throws {
        let url = try #require(URL(string: address))
        #expect(ReviewCommitLink.hash(in: url) == nil)
    }
}
