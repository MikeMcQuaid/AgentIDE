/// Scores candidates against a typed query the way editor file
/// finders do: every query character must appear in order, and runs,
/// word starts and path basenames score higher.
public enum FuzzyMatcher {
    // MARK: Public

    /// The candidates matching the query, best first. An empty query
    /// returns the candidates unchanged.
    public static func rank(_ candidates: [String], query: String) -> [String] {
        let trimmed = query.lowercased().filter { $0.isWhitespace == false }
        guard trimmed.isEmpty == false else {
            return candidates
        }

        return candidates
            .compactMap { candidate in score(candidate, query: trimmed).map { (candidate, $0) } }
            .sorted { first, second in
                // Equal scores prefer the shorter, more direct path.
                first.1 == second.1 ? first.0.count < second.0.count : first.1 > second.1
            }
            .map(\.0)
    }

    /// The match score, nil when the query's characters do not all
    /// appear in order.
    public static func score(_ candidate: String, query: String) -> Int? {
        let characters = Array(candidate.lowercased())
        let queryCharacters = Array(query)
        var score = 0
        var queryIndex = 0
        var previousMatch = -2
        let basenameStart = characters.lastIndex(of: "/").map { $0 + 1 } ?? 0

        for (index, character) in characters.enumerated() where queryIndex < queryCharacters.count {
            guard character == queryCharacters[queryIndex] else {
                continue
            }

            score += 1
            if index == previousMatch + 1 {
                score += consecutiveBonus
            }
            let separators: Set<Character> = ["/", "-", "_", "."]
            if index == 0 || separators.contains(characters[index - 1]) {
                score += wordStartBonus
            }
            if index >= basenameStart {
                score += basenameBonus
            }
            previousMatch = index
            queryIndex += 1
        }
        return queryIndex == queryCharacters.count ? score : nil
    }

    // MARK: Private

    private static let consecutiveBonus = 3
    private static let wordStartBonus = 2
    private static let basenameBonus = 1
}
