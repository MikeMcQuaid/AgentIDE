import Foundation

/// Filters numbered items (issues, pull requests) by what is typed
/// into their picker: digits, with or without a leading `#`, match
/// any part of a number, exact matches first; anything else ranks
/// titles through `FuzzyMatcher`.
public enum NumberedItemSearch {
    /// The items matching the query, best first. An empty query
    /// returns the items unchanged.
    public static func rank<Item: NumberedItem>(_ items: [Item], query: String) -> [Item] {
        var trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("#") {
            trimmed.removeFirst()
        }
        guard trimmed.isEmpty == false else {
            return items
        }

        if trimmed.allSatisfy(\.isASCII), trimmed.allSatisfy(\.isNumber) {
            return items.filter { String($0.number) == trimmed }
                + items.filter { String($0.number) != trimmed && String($0.number).contains(trimmed) }
        }

        let normalised = FuzzyMatcher.normalise(trimmed)
        return items
            .compactMap { item in FuzzyMatcher.score(item.title, query: normalised).map { (item, $0) } }
            // Stable, so equal scores keep GitHub's order, newest first.
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }
}
