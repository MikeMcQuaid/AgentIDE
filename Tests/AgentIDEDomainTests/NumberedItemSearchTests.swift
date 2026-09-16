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

    @Test
    func `text matches titles`() {
        #expect(rank("picker") == [123])
        #expect(rank("sidebar") == [7])
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
        NumberedItemSearch.rank(issues, query: query, number: \.number, title: \.title).map(\.number)
    }
}
