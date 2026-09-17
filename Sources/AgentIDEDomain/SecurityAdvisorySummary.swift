/// A repository security advisory still in triage or draft, enough
/// to pick one as a prompt source. Never cached: its title describes
/// an unpublished vulnerability.
public struct SecurityAdvisorySummary: ReferencedItem, Hashable, Sendable {
    // MARK: Lifecycle

    /// Creates a summary.
    public init(ghsaID: String, title: String) {
        self.ghsaID = ghsaID
        self.title = title
    }

    // MARK: Public

    /// The advisory's GHSA id, which GitHub refers to it by.
    public let ghsaID: String

    /// The advisory's summary line.
    public let title: String

    /// The stable identity, the GHSA id.
    public var id: String {
        ghsaID
    }

    /// The label GitHub refers to it by, the GHSA id.
    public var reference: String {
        ghsaID
    }
}
