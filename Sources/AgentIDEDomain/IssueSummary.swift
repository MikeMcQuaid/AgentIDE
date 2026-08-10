/// An open issue, enough to pick one as a prompt source.
public struct IssueSummary: Identifiable, Hashable, Sendable, Codable {
    // MARK: Lifecycle

    /// Creates a summary.
    public init(number: Int, title: String) {
        self.number = number
        self.title = title
    }

    // MARK: Public

    /// The issue number.
    public let number: Int

    /// The issue title.
    public let title: String

    /// The stable identity, the issue number.
    public var id: Int {
        number
    }
}
