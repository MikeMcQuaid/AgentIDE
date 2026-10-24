import Foundation
@testable import TerminalUI
import Testing

struct ReviewCommitLinkTests {
    @Test
    func `commit listings accept literal hashes`() throws {
        let url = try #require(URL(string: "agentide-commit:d904c"))
        #expect(ReviewCommitLink.hash(in: url) == "d904c")
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
