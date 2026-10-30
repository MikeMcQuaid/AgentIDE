import Foundation

/// Filters referenced items (issues, pull requests, advisories) by
/// what is typed into their picker: digits, with or without a
/// leading `#`, match any part of a number, exact matches first;
/// anything else matches a reference containing it, a GHSA id's
/// case aside, and then ranks titles through `FuzzyMatcher`.
public enum ReferencedItemSearch {
    /// The items matching the query, best first. An empty query
    /// returns the items unchanged.
    public static func rank<Item: ReferencedItem>(_ items: [Item], query: String) -> [Item] {
        var trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("#") {
            trimmed.removeFirst()
        }
        guard trimmed.isEmpty == false else {
            return items
        }

        if trimmed.allSatisfy(\.isASCII), trimmed.allSatisfy(\.isNumber) {
            return items.filter { $0.reference == "#" + trimmed }
                + items.filter { $0.reference != "#" + trimmed && $0.reference.contains(trimmed) }
        }

        let byReference = items.filter { $0.reference.range(of: trimmed, options: .caseInsensitive) != nil }
        let referenced = Set(byReference.map(\.reference))
        let normalised = FuzzyMatcher.normalise(trimmed)
        return byReference + items
            .filter { referenced.contains($0.reference) == false }
            .compactMap { item in FuzzyMatcher.score(item.title, query: normalised).map { (item, $0) } }
            // Stable, so equal scores keep GitHub's order, newest first.
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }
}
