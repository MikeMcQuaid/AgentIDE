import Foundation
@testable import TerminalUI
import Testing

struct ReviewCommitLinkTests {
    @Test
    func `commit listings accept literal hashes`() throws {
        let url = try #require(URL(string: "sanductor-commit:d904c"))
        #expect(ReviewCommitLink.hash(in: url) == "d904c")
    }

    @Test(arguments: [
        "https://example.com/d904c", "sanductor-commit:--help", "sanductor-commit:HEAD",
        "sanductor-commit:d90", "sanductor-commit:d904c/path", "sanductor-commit:d904c?other",
        "sanductor-commit:d904c%20HEAD", "sanductor-commit://d904c",
    ])
    func `only literal commit hashes can be requested`(_ address: String) throws {
        let url = try #require(URL(string: address))
        #expect(ReviewCommitLink.hash(in: url) == nil)
    }
}
