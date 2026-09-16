import AgentIDEDomain
import Testing

/// Exercises the issue and pull request picker search.
struct NumberedItemSearchTests {
    // MARK: Internal

    @Test
    func `digits match numbers, exact first`() {
        #expect(rank("12") == [12, 123])
        #expect(rank("#123") == [123])
        #expect(rank("9").isEmpty)
    }

    @Test(arguments: [
        ("12", [12, 123]),
        ("#12", [12, 123]),
        (" \t#12 \t", [12, 123]),
        ("\n#12\r\n", [12, 123]),
        ("2", [123, 12]),
        ("#23", [123]),
        ("13", []),
        ("picker", [123]),
    ])
    func `pull requests match numbers and titles in the same search`(query: String, expected: [Int]) {
        let pullRequests = issues.reversed().map { issue in
            PullRequestSummary(
                number: issue.number,
                title: issue.title,
                url: "",
                headBranch: "",
                mergeable: "",
                reviewDecision: "",
                checks: "",
            )
        }
        #expect(NumberedItemSearch.rank(pullRequests, query: query).map(\.number) == expected)
    }

    @Test
    func `text matches titles`() {
        #expect(rank("picker") == [123])
        #expect(rank("sidebar") == [7])
    }

    @Test
    func `word starts in titles rank first`() {
        #expect(rank("ap") == [123, 12])
    }

    @Test
    func `empty queries keep the given order`() {
        #expect(rank(" ") == [12, 123, 7])
        #expect(rank("#") == [12, 123, 7])
    }

    // MARK: Private

    private let issues = [
        IssueSummary(number: 12, title: "Crash when opening a fork"),
        IssueSummary(number: 123, title: "Searchable issue picker"),
        IssueSummary(number: 7, title: "Colour the sidebar"),
    ]

    private func rank(_ query: String) -> [Int] {
        NumberedItemSearch.rank(issues, query: query).map(\.number)
    }
}
