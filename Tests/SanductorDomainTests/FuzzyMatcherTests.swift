import SanductorDomain
import Testing

/// Exercises the file-finder ranking.
struct FuzzyMatcherTests {
    @Test
    func `requires every query character in order`() {
        #expect(FuzzyMatcher.score("Sources/App/RootView.swift", query: "rootview") != nil)
        #expect(FuzzyMatcher.score("Sources/App/RootView.swift", query: "viewroot") == nil)
        #expect(FuzzyMatcher.score("abc", query: "abcd") == nil)
    }

    @Test
    func `ranks basename and consecutive matches first`() {
        let ranked = FuzzyMatcher.rank(
            [
                "Tests/SanductorDataTests/GitClientIntegrationTests.swift",
                "Sources/SanductorData/GitClient.swift",
                "Sources/SanductorDomain/DiffParser.swift",
            ],
            query: "gitclient",
        )
        #expect(ranked.first == "Sources/SanductorData/GitClient.swift")
        #expect(ranked.contains("Sources/SanductorDomain/DiffParser.swift") == false)
    }

    @Test
    func `a space starts a word`() {
        let ranked = FuzzyMatcher.rank(["Fix reopen", "Fix an open"], query: "op")
        #expect(ranked == ["Fix an open", "Fix reopen"])
    }

    @Test
    func `empty queries keep the given order`() {
        #expect(FuzzyMatcher.rank(["b", "a"], query: " ") == ["b", "a"])
    }
}
