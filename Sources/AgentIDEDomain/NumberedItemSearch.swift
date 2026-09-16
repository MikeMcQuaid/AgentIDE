import Foundation

/// Filters numbered items (issues, pull requests) by what is typed
/// into their picker: digits, with or without a leading `#`, match
/// numbers, the exact one first and then those starting with the
/// digits; anything else ranks titles through `FuzzyMatcher`.
public enum NumberedItemSearch {
    /// The items matching the query, best first. An empty query
    /// returns the items unchanged.
    public static func rank<Item>(
        _ items: [Item],
        query: String,
        number: (Item) -> Int,
        title: (Item) -> String,
    ) -> [Item] {
        var trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("#") {
            trimmed.removeFirst()
        }
        guard trimmed.isEmpty == false else {
            return items
        }

        if trimmed.allSatisfy(\.isASCII), trimmed.allSatisfy(\.isNumber) {
            let exact = items.filter { String(number($0)) == trimmed }
            let prefixed = items.filter { String(number($0)) != trimmed && String(number($0)).hasPrefix(trimmed) }
            return exact + prefixed
        }

        let lowered = trimmed.lowercased().filter { $0.isWhitespace == false }
        return items
            .compactMap { item in FuzzyMatcher.score(title(item), query: lowered).map { (item, $0) } }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }
}
