import AgentIDEDomain
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
                "Tests/AgentIDEDataTests/GitClientIntegrationTests.swift",
                "Sources/AgentIDEData/GitClient.swift",
                "Sources/AgentIDEDomain/DiffParser.swift",
            ],
            query: "gitclient",
        )
        #expect(ranked.first == "Sources/AgentIDEData/GitClient.swift")
        #expect(ranked.contains("Sources/AgentIDEDomain/DiffParser.swift") == false)
    }

    @Test
    func `empty queries keep the given order`() {
        #expect(FuzzyMatcher.rank(["b", "a"], query: " ") == ["b", "a"])
    }
}
